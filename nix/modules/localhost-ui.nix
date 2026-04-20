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
    CN = OL-C Local CA

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
  options.olc.localhost.tlsPackage = lib.mkOption {
    internal = true;
    type = lib.types.package;
    default = olcLocalhostTls;
    description = "Generated localhost TLS material for the in-guest OL-C UI.";
  };

  config = {
    security.pki.certificates = [
      (builtins.readFile "${localhostTls}/ca.crt")
    ];

    systemd.services.ol-c-terminal = {
      description = "OL-C stable browser terminal service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        OLC_BASH = "${pkgs.bashInteractive}/bin/bash";
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
      description = "OL-C local HTTPS UI";
      after = [ "network.target" "ol-c-terminal.service" ];
      wants = [ "ol-c-terminal.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        OLC_FIREFOX = "${pkgs.firefox}/bin/firefox";
        OLC_FIREFOX_VERSION = pkgs.firefox.version;
        OLC_PACTL = "${pkgs.pulseaudio}/bin/pactl";
        OLC_PULSE_SERVER = "unix:/run/user/1000/pulse/native";
        OLC_TERMINAL_UPSTREAM = "https://127.0.0.1:9443";
        OLC_TLS_CERT = "${localhostTls}/server.crt";
        OLC_TLS_KEY = "${localhostTls}/server.key";
      };

      serviceConfig = {
        ExecStart = "${pkgs.nodejs}/bin/node ${../../localhost-ui}/dev-supervisor.mjs";
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
