{ lib, modulesPath, pkgs, ... }:

{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  system.stateVersion = "25.11";
  ids.uids.nixbld = lib.mkForce 700;

  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  boot.kernelParams = [
    "console=ttyS0,115200n8"
  ];

  services.journald.extraConfig = ''
    Storage=persistent
  '';

  networking.hostName = "ol-c-browser";

  systemd.tmpfiles.rules = [
    "d /var/lib/ol-c 0755 root root -"
    "d /var/lib/ol-c/journal-mirror 0755 root root -"
  ];

  systemd.generators.olc-nested-fast-boot = pkgs.writeShellScript "olc-nested-fast-boot-generator" ''
    set -euo pipefail

    output_dir="$1"
    dmi_serial_path="/sys/class/dmi/id/product_serial"
    serial=""

    if [ ! -r "$dmi_serial_path" ]; then
      exit 0
    fi

    serial="$(${pkgs.coreutils}/bin/tr -d '\n' < "$dmi_serial_path")"

    mask_unit() {
      ${pkgs.coreutils}/bin/ln -sf /dev/null "$output_dir/$1"
    }

    if printf '%s\n' "$serial" | ${pkgs.gnugrep}/bin/grep -Fq 'olc-fast-boot=1'; then
      mask_unit systemd-journal-flush.service
      mask_unit systemd-random-seed.service
    fi

    if printf '%s\n' "$serial" | ${pkgs.gnugrep}/bin/grep -Fq 'olc-net=none'; then
      mask_unit dhcpcd.service
    fi
  '';

  systemd.services.olc-journal-lineage = {
    description = "Record ol-c VM lineage marker";
    after = [ "systemd-journald.service" ];
    wants = [ "systemd-journald.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -euo pipefail

      machine_id="$(cat /etc/machine-id)"
      boot_id="$(cat /proc/sys/kernel/random/boot_id)"
      lifecycle_id=""
      parent_machine_id=""
      parent_depth=""
      depth="0"
      dmi_serial_path="/sys/class/dmi/id/product_serial"

      if [ -r "$dmi_serial_path" ]; then
        serial="$(${pkgs.coreutils}/bin/tr -d '\n' < "$dmi_serial_path")"
        lifecycle_id="$(printf '%s\n' "$serial" | ${pkgs.gnused}/bin/sed -n 's/^.*olc-lifecycle-id=\([^;]*\).*$/\1/p')"
        parent_machine_id="$(printf '%s\n' "$serial" | ${pkgs.gnused}/bin/sed -n 's/^.*olc-parent-machine-id=\([^;]*\).*$/\1/p')"
        parent_depth="$(printf '%s\n' "$serial" | ${pkgs.gnused}/bin/sed -n 's/^.*olc-parent-depth=\([0-9][0-9]*\).*$/\1/p')"
        if [ -n "$parent_depth" ]; then
          depth="$((parent_depth + 1))"
        fi
      fi

      {
        printf 'MESSAGE=ol-c vm lineage marker\n'
        printf 'SYSLOG_IDENTIFIER=olc-vm-lineage\n'
        printf 'PRIORITY=6\n'
        printf 'OLC_VM_MACHINE_ID=%s\n' "$machine_id"
        printf 'OLC_VM_BOOT_ID=%s\n' "$boot_id"
        printf 'OLC_VM_DEPTH=%s\n' "$depth"
        if [ -n "$lifecycle_id" ]; then
          printf 'OLC_VM_LIFECYCLE_ID=%s\n' "$lifecycle_id"
        fi
        if [ -n "$parent_machine_id" ]; then
          printf 'OLC_VM_PARENT_MACHINE_ID=%s\n' "$parent_machine_id"
        fi
      } | ${pkgs.util-linux}/bin/logger --journald

      {
        printf 'OLC_VM_MACHINE_ID=%s\n' "$machine_id"
        printf 'OLC_VM_BOOT_ID=%s\n' "$boot_id"
        printf 'OLC_VM_DEPTH=%s\n' "$depth"
        if [ -n "$lifecycle_id" ]; then
          printf 'OLC_VM_LIFECYCLE_ID=%s\n' "$lifecycle_id"
        fi
        if [ -n "$parent_machine_id" ]; then
          printf 'OLC_VM_PARENT_MACHINE_ID=%s\n' "$parent_machine_id"
        fi
      } > /run/olc-vm-lineage.env
    '';
  };

  systemd.services.olc-journal-mirror = {
    description = "Mirror the current boot journal into /source";
    after = [ "systemd-journald.service" "olc-journal-lineage.service" ];
    wants = [ "systemd-journald.service" "olc-journal-lineage.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 2;
      RequiresMountsFor = "/source";
    };
    script = ''
      set -euo pipefail

      state_dir="/var/lib/ol-c/journal-mirror"
      cursor_file="$state_dir/current.cursor"
      boot_file="$state_dir/current.boot-id"
      machine_id="$(cat /etc/machine-id)"
      current_boot_id="$(cat /proc/sys/kernel/random/boot_id)"
      systemd_journal_remote="${pkgs.systemd}/lib/systemd/systemd-journal-remote"
      current_journal_dir="/source/.olc-debug/journal"
      current_journal_file="$current_journal_dir/''${machine_id}-''${current_boot_id}.journal"

      mkdir -p "$state_dir"

      if [ ! -f "$boot_file" ] || [ "$(${pkgs.coreutils}/bin/cat "$boot_file")" != "$current_boot_id" ]; then
        rm -f "$cursor_file"
        printf '%s\n' "$current_boot_id" > "$boot_file"
      fi

      while true; do
        tmpdir="$(${pkgs.coreutils}/bin/mktemp -d "$state_dir/export.XXXXXX")"
        export_file="$tmpdir/current.export"
        last_cursor=""

        mkdir -p "$current_journal_dir"
        chmod 0755 /source/.olc-debug "$current_journal_dir" 2>/dev/null || true

        if [ -s "$cursor_file" ]; then
          cursor="$(${pkgs.coreutils}/bin/cat "$cursor_file")"
          ${pkgs.systemd}/bin/journalctl \
            -b \
            --after-cursor="$cursor" \
            --output=export \
            --all \
            --no-pager > "$export_file"
        else
          ${pkgs.systemd}/bin/journalctl \
            -b \
            --output=export \
            --all \
            --no-pager > "$export_file"
        fi

        if [ -s "$export_file" ]; then
          last_cursor="$(${pkgs.gnugrep}/bin/grep -a '^__CURSOR=' "$export_file" | ${pkgs.coreutils}/bin/tail -n 1 | ${pkgs.coreutils}/bin/cut -d= -f2-)"
          if [ -n "$last_cursor" ]; then
            "$systemd_journal_remote" -o "$current_journal_file" - < "$export_file"
            chmod 0644 "$current_journal_file"
            printf '%s\n' "$last_cursor" > "$cursor_file"
          fi
        fi

        rm -rf "$tmpdir"
        sleep 0.2
      done
    '';
  };
}
