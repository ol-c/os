{ config, lib, pkgs, ... }:

let
  olcLocalhostTls = pkgs.runCommand "ol-c-localhost-tls" {
    nativeBuildInputs = [ pkgs.openssl ];
  } ''
    mkdir -p "$out"

    cat > ca.cnf <<'EOF'
    [req]
    distinguished_name = dn
    x509_extensions = v3_ca
    prompt = no

    [dn]
    CN = ol-c Local CA

    [v3_ca]
    basicConstraints = critical, CA:true
    keyUsage = critical, keyCertSign, cRLSign
    subjectKeyIdentifier = hash
    EOF

    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
      -keyout "$out/ca.key" \
      -out "$out/ca.crt" \
      -config ca.cnf

    cat > server.cnf <<'EOF'
    [req]
    distinguished_name = dn
    req_extensions = v3_req
    prompt = no

    [dn]
    CN = localhost

    [v3_req]
    basicConstraints = CA:false
    keyUsage = critical, digitalSignature, keyEncipherment
    extendedKeyUsage = serverAuth
    subjectAltName = @alt_names

    [alt_names]
    DNS.1 = localhost
    IP.1 = 127.0.0.1
    EOF

    openssl req -new -newkey rsa:2048 -nodes -sha256 \
      -keyout "$out/server.key" \
      -out server.csr \
      -config server.cnf

    openssl x509 -req -sha256 -days 3650 \
      -in server.csr \
      -CA "$out/ca.crt" \
      -CAkey "$out/ca.key" \
      -CAcreateserial \
      -out "$out/server.crt" \
      -extensions v3_req \
      -extfile server.cnf

    rm -f ca.cnf server.cnf server.csr "$out/ca.key" "$out/ca.srl"
  '';

  localhostTls = config.olc.localhost.tlsPackage;
in {
  options.olc.setup.prefillFirstUser = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule {
      options = {
        username = lib.mkOption {
          type = lib.types.str;
        };
        password = lib.mkOption {
          type = lib.types.str;
        };
      };
    });
    default = null;
    description = "Optional test-only first-user prefill path for VM fixtures.";
  };

  options.olc.localhost.tlsPackage = lib.mkOption {
    internal = true;
    type = lib.types.package;
    default = olcLocalhostTls;
    description = "Generated localhost TLS material for the in-guest ol-c UI.";
  };

  config = {
    security.pki.certificates = [
      (builtins.readFile "${localhostTls}/ca.crt")
    ];

    services.homed.enable = true;

    systemd.services.ol-c-prefill-first-user = lib.mkIf (config.olc.setup.prefillFirstUser != null) {
      description = "ol-c test-only first-user prefill";
      after = [ "systemd-homed.service" ];
      before = [ "getty@tty1.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
      };

      script = ''
        set -euo pipefail

        if ${pkgs.getent}/bin/getent group olc-admin | ${pkgs.gnugrep}/bin/grep -Eq '^[^:]*:[^:]*:[^:]*:[^[:space:]]'; then
          exit 0
        fi

        tmpdir="$(mktemp -d)"
        trap 'rm -rf "$tmpdir"' EXIT
        cat > "$tmpdir/${config.olc.setup.prefillFirstUser.username}.password" <<'EOF'
        ${config.olc.setup.prefillFirstUser.password}
        ${config.olc.setup.prefillFirstUser.password}
        EOF

        ${pkgs.util-linux}/bin/script -qefc \
          "${pkgs.systemd}/bin/homectl create ${lib.escapeShellArg config.olc.setup.prefillFirstUser.username} --storage=luks --disk-size=8G --uid=1000 --home-dir=/home/${config.olc.setup.prefillFirstUser.username} --shell=${pkgs.bashInteractive}/bin/bash --member-of=olc-admin,wheel,kvm --access-mode=0700 --no-pager" \
          /dev/null \
          < "$tmpdir/${config.olc.setup.prefillFirstUser.username}.password"

        ${pkgs.systemd}/bin/homectl inspect ${lib.escapeShellArg config.olc.setup.prefillFirstUser.username} --json=short --no-pager >/dev/null
      '';
    };

    systemd.services.ol-c-terminal = {
      description = "ol-c stable browser terminal service";
      after = [ "network.target" "systemd-homed.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        OLC_BASH = "${pkgs.bashInteractive}/bin/bash";
        OLC_GETENT = "${pkgs.getent}/bin/getent";
        OLC_LOGINCTL = "${pkgs.systemd}/bin/loginctl";
        OLC_TERMINAL_CLIENT_CSS = "${../../terminal-client/dist/terminal.css}";
        OLC_TERMINAL_CLIENT_JS = "${../../terminal-client/dist/terminal.js}";
        OLC_TERMINAL_PORT = "9443";
        OLC_TERMINAL_PUBLIC_URL = "https://localhost:9443";
        OLC_TLS_CERT = "${localhostTls}/server.crt";
        OLC_TLS_KEY = "${localhostTls}/server.key";
        OLC_TTYD = "${pkgs.ttyd}/bin/ttyd";
      };

      serviceConfig = {
        ExecStart = "${pkgs.nodejs}/bin/node ${../../localhost-ui}/terminal-server.mjs";
        Restart = "on-failure";
        RestartSec = "1s";
      };
    };

    systemd.services.ol-c-ui = {
      description = "ol-c local HTTPS UI";
      after = [ "network.target" "ol-c-terminal.service" "systemd-homed.service" ];
      wants = [ "ol-c-terminal.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        OLC_FIREFOX = "${pkgs.firefox}/bin/firefox";
        OLC_FIREFOX_VERSION = pkgs.firefox.version;
        OLC_GETENT = "${pkgs.getent}/bin/getent";
        OLC_HOMECTL = "${pkgs.systemd}/bin/homectl";
        OLC_LOGINCTL = "${pkgs.systemd}/bin/loginctl";
        OLC_LOGIN_SHELL = "${pkgs.bashInteractive}/bin/bash";
        OLC_PACTL = "${pkgs.pulseaudio}/bin/pactl";
        OLC_PULSE_SERVER = "unix:/run/user/1000/pulse/native";
        OLC_SCRIPT = "${pkgs.util-linux}/bin/script";
        OLC_SETUP_USER = "olc-setup";
        OLC_SYSTEMD_RUN = "${pkgs.systemd}/bin/systemd-run";
        OLC_TERMINAL_UPSTREAM = "https://127.0.0.1:9443";
        OLC_TLS_CERT = "${localhostTls}/server.crt";
        OLC_TLS_KEY = "${localhostTls}/server.key";
      };

      serviceConfig = {
        ExecStart = "${pkgs.nodejs}/bin/node ${../../localhost-ui}/dev-supervisor.mjs";
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        NoNewPrivileges = true;
        Restart = "on-failure";
        RestartSec = "1s";
      };
    };

    systemd.services.olc-vm-ready = {
      description = "ol-c embedded VM ready marker";
      after = [ "ol-c-ui.service" "olc-journal-lineage.service" ];
      wants = [ "ol-c-ui.service" "olc-journal-lineage.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
      };

      script = ''
        set -euo pipefail

        machine_id=""
        boot_id=""
        depth=""
        parent_machine_id=""
        lineage_env="/run/olc-vm-lineage.env"
        bidi_env_path=""
        bidi_ready=0

        if [ -r "$lineage_env" ]; then
          # shellcheck disable=SC1091
          . "$lineage_env"
          machine_id="''${OLC_VM_MACHINE_ID:-}"
          boot_id="''${OLC_VM_BOOT_ID:-}"
          depth="''${OLC_VM_DEPTH:-}"
          parent_machine_id="''${OLC_VM_PARENT_MACHINE_ID:-}"
        fi

        ready_deadline_ms="$((($(date +%s%3N)) + 30000))"

        resolve_active_bidi_env() {
          local active_session session_info session_name session_remote session_state passwd_entry session_uid

          active_session="$(${pkgs.systemd}/bin/loginctl show-seat seat0 --property=ActiveSession --value 2>/dev/null || true)"
          active_session="$(printf '%s\n' "$active_session" | ${pkgs.gnused}/bin/sed -n '1p')"
          [ -n "$active_session" ] || return 1

          session_info="$(${pkgs.systemd}/bin/loginctl show-session "$active_session" \
            --property=Name \
            --property=Remote \
            --property=State \
            2>/dev/null || true)"
          session_name="$(printf '%s\n' "$session_info" | ${pkgs.gnused}/bin/sed -n 's/^Name=//p' | ${pkgs.gnused}/bin/sed -n '1p')"
          session_remote="$(printf '%s\n' "$session_info" | ${pkgs.gnused}/bin/sed -n 's/^Remote=//p' | ${pkgs.gnused}/bin/sed -n '1p')"
          session_state="$(printf '%s\n' "$session_info" | ${pkgs.gnused}/bin/sed -n 's/^State=//p' | ${pkgs.gnused}/bin/sed -n '1p')"
          [ -n "$session_name" ] || return 1
          [ "$session_remote" != "yes" ] || return 1
          if [ -n "$session_state" ] && [ "$session_state" != "active" ]; then
            return 1
          fi

          passwd_entry="$(${pkgs.getent}/bin/getent passwd "$session_name" 2>/dev/null || true)"
          [ -n "$passwd_entry" ] || return 1
          session_uid="$(printf '%s\n' "$passwd_entry" | ${pkgs.coreutils}/bin/cut -d: -f3)"
          [ -n "$session_uid" ] || return 1

          printf '/run/user/%s/ol-c-firefox/bidi.env\n' "$session_uid"
        }

        while true; do
          bidi_env_path="$(resolve_active_bidi_env || true)"
          if [ -n "$bidi_env_path" ] \
            && [ -r "$bidi_env_path" ] \
            && ${pkgs.gnugrep}/bin/grep -Eq '^OLC_FIREFOX_BIDI_WS_URL=ws://127\.0\.0\.1:[0-9]+/session$' "$bidi_env_path"; then
            bidi_ready=1
            break
          fi

          if [ "$(date +%s%3N)" -ge "$ready_deadline_ms" ]; then
            echo "error: timed out waiting for active Firefox BiDi metadata before emitting the embedded VM ready marker" >&2
            exit 1
          fi

          sleep 0.1
        done

        {
          printf 'MESSAGE=ol-c vm ready for embedded control\n'
          printf 'SYSLOG_IDENTIFIER=olc-vm-ready\n'
          printf 'PRIORITY=6\n'
          printf 'OLC_VM_READY=embedded-control-ready\n'
          printf 'OLC_VM_READY_SURFACE=https://localhost/\n'
          if [ "$bidi_ready" = "1" ]; then
            printf 'OLC_VM_READY_CONTROL=bidi\n'
          fi
          if [ -n "$bidi_env_path" ]; then
            printf 'OLC_FIREFOX_BIDI_ENV_PATH=%s\n' "$bidi_env_path"
          fi
          if [ -n "$machine_id" ]; then
            printf 'OLC_VM_MACHINE_ID=%s\n' "$machine_id"
          fi
          if [ -n "$boot_id" ]; then
            printf 'OLC_VM_BOOT_ID=%s\n' "$boot_id"
          fi
          if [ -n "$depth" ]; then
            printf 'OLC_VM_DEPTH=%s\n' "$depth"
          fi
          if [ -n "$parent_machine_id" ]; then
            printf 'OLC_VM_PARENT_MACHINE_ID=%s\n' "$parent_machine_id"
          fi
        } | ${pkgs.util-linux}/bin/logger --journald
      '';
    };

    systemd.services.olc-vm-operator = {
      description = "ol-c embedded VM BiDi operator";
      after = [ "ol-c-ui.service" "olc-vm-ready.service" "olc-journal-lineage.service" ];
      wants = [ "ol-c-ui.service" "olc-vm-ready.service" "olc-journal-lineage.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        OLC_ENV = "${pkgs.coreutils}/bin/env";
        OLC_FIREFOX_BIDI_SCRIPT = "/source/tools/olc-firefox-bidi.mjs";
        OLC_FIREFOX_BIDI_URL_HELPER = "/run/current-system/sw/bin/olc-firefox-bidi-url";
        OLC_GETENT = "${pkgs.getent}/bin/getent";
        OLC_LOGINCTL = "${pkgs.systemd}/bin/loginctl";
        OLC_NODE = "${pkgs.nodejs}/bin/node";
        OLC_RUNUSER = "${pkgs.util-linux}/bin/runuser";
        OLC_SOURCE_ROOT = "/source";
        OLC_VM_OPERATOR_ROOT = "/source/.olc-debug/operator/current";
      };

      serviceConfig = {
        ExecStart = "${pkgs.nodejs}/bin/node /source/tools/olc-vm-operator.mjs";
        RequiresMountsFor = "/source";
        Restart = "always";
        RestartSec = "1s";
      };
    };

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    security.rtkit.enable = true;
  };
}
