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
          "${pkgs.systemd}/bin/homectl create ${lib.escapeShellArg config.olc.setup.prefillFirstUser.username} --storage=luks --uid=1000 --home-dir=/home/${config.olc.setup.prefillFirstUser.username} --shell=${pkgs.bashInteractive}/bin/bash --member-of=olc-admin,wheel,kvm --access-mode=0700 --no-pager" \
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

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };

    security.rtkit.enable = true;
  };
}
