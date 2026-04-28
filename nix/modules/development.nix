{ pkgs, ... }:

let
  codexVersion = "0.120.0";
  codexCommand = pkgs.writeShellScriptBin "codex" ''
    set -eu

    if [ -z "''${HOME:-}" ]; then
      HOME="$(${pkgs.getent}/bin/getent passwd "$(id -u)" | ${pkgs.coreutils}/bin/cut -d: -f6)"
      export HOME
    fi

    export CODEX_HOME="''${CODEX_HOME:-''${HOME}/.codex}"
    export CODEX_MODEL="''${CODEX_MODEL:-gpt-5.4}"
    export NO_UPDATE_NOTIFIER="''${NO_UPDATE_NOTIFIER:-1}"

    mkdir -p "$CODEX_HOME"

    exec ${pkgs.nodejs}/bin/npx \
      --yes \
      @openai/codex@${codexVersion} \
      --model "$CODEX_MODEL" \
      --dangerously-bypass-approvals-and-sandbox \
      "$@"
  '';
  olcLaunchTestVm = pkgs.writeShellScriptBin "olc-launch-test-vm" ''
    export OLC_DEFAULT_NOVNC_DIR="''${OLC_DEFAULT_NOVNC_DIR:-${pkgs.novnc}/share/webapps/novnc}"
    export OLC_DEFAULT_QEMU_BIN="''${OLC_DEFAULT_QEMU_BIN:-${pkgs.qemu_kvm}/bin/qemu-system-x86_64}"
    exec ${pkgs.bash}/bin/bash ${../../olc-launch-test-vm} "$@"
  '';
  olcVmctl = pkgs.writeShellScriptBin "olc-vmctl" ''
    source_root="''${OLC_SOURCE_ROOT:-/source}"
    if [ -x "$source_root/olc-vmctl" ]; then
      exec "$source_root/olc-vmctl" "$@"
    fi

    exec ${pkgs.nodejs}/bin/node ${../../tools}/olc-vmctl.mjs "$@"
  '';
  olcFirefoxSource = pkgs.writeShellScriptBin "olc-firefox-source" ''
    source_root="''${OLC_SOURCE_ROOT:-/source}"
    if [ -x "$source_root/olc-firefox-source" ]; then
      exec ${pkgs.bash}/bin/bash "$source_root/olc-firefox-source" "$@"
    fi

    exec ${pkgs.bash}/bin/bash ${../../olc-firefox-source} "$@"
  '';
  olcFirefoxBidiUrl = pkgs.writeShellScriptBin "olc-firefox-bidi-url" ''
    source_root="''${OLC_SOURCE_ROOT:-/source}"
    if [ -x "$source_root/tools/olc-firefox-bidi-url.sh" ]; then
      exec ${pkgs.bash}/bin/bash "$source_root/tools/olc-firefox-bidi-url.sh" "$@"
    fi

    exec ${pkgs.bash}/bin/bash ${../../tools}/olc-firefox-bidi-url.sh "$@"
  '';
  olcFirefoxBidi = pkgs.writeShellScriptBin "olc-firefox-bidi" ''
    source_root="''${OLC_SOURCE_ROOT:-/source}"
    if [ -x "$source_root/tools/olc-firefox-bidi.mjs" ]; then
      exec ${pkgs.nodejs}/bin/node "$source_root/tools/olc-firefox-bidi.mjs" "$@"
    fi

    exec ${pkgs.nodejs}/bin/node ${../../tools}/olc-firefox-bidi.mjs "$@"
  '';
  olcVmBidi = pkgs.writeShellScriptBin "olc-vm-bidi" ''
    source_root="''${OLC_SOURCE_ROOT:-/source}"
    if [ -x "$source_root/tools/olc-vm-bidi.mjs" ]; then
      exec ${pkgs.nodejs}/bin/node "$source_root/tools/olc-vm-bidi.mjs" "$@"
    fi

    exec ${pkgs.nodejs}/bin/node ${../../tools}/olc-vm-bidi.mjs "$@"
  '';
in {
  environment.systemPackages = [
    codexCommand
    olcFirefoxSource
    olcFirefoxBidi
    olcFirefoxBidiUrl
    olcLaunchTestVm
    olcVmBidi
    olcVmctl
    pkgs.sudo
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
  };

  security.sudo.wheelNeedsPassword = false;

  systemd.tmpfiles.rules = [
    "d /var/lib/ol-c 0755 root root -"
    "d /var/lib/ol-c/vms 0775 root olc-admin -"
    "d /var/lib/ol-c/vms/tmp 0775 root olc-admin -"
  ];
}
