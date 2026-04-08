{ lib, pkgs, ... }:

let
  secureosLocalhostTls = pkgs.runCommand "secureos-localhost-tls" {
    nativeBuildInputs = [ pkgs.openssl ];
  } ''
    mkdir -p "$out"

    cat > ca.cnf <<'EOF'
    [req]
    distinguished_name = dn
    x509_extensions = v3_ca
    prompt = no

    [dn]
    CN = SecureOS Local CA

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

  secureosUiServer = pkgs.writeText "secureos-ui-server.mjs" ''
    import { readFileSync } from 'node:fs';
    import { createServer } from 'node:https';

    const marker = 'MILESTONE3_LOCALHOST_UI_OK';
    const html = `<!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>SecureOS</title>
        <style>
          :root {
            color-scheme: dark;
            font-family: sans-serif;
            background: #09111f;
            color: #f4f7fb;
          }

          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            background:
              radial-gradient(circle at top, rgba(94, 234, 212, 0.18), transparent 30%),
              linear-gradient(180deg, #0b1220, #050814);
          }

          main {
            width: min(44rem, calc(100vw - 3rem));
            padding: 2rem;
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 1.25rem;
            background: rgba(9, 17, 31, 0.82);
            box-shadow: 0 2rem 5rem rgba(0, 0, 0, 0.35);
          }

          h1, p {
            margin: 0;
          }

          p {
            margin-top: 1rem;
            line-height: 1.5;
            color: #c7d2e3;
          }

          code {
            font-family: monospace;
            color: #5eead4;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>SecureOS control surface</h1>
          <p>Firefox now boots to <code>https://localhost</code>, served inside the guest by a Node.js process on port <code>443</code>.</p>
          <p id="proof">''${marker}</p>
        </main>
      </body>
    </html>`;

    const server = createServer({
      key: readFileSync('${secureosLocalhostTls}/server.key'),
      cert: readFileSync('${secureosLocalhostTls}/server.crt'),
    }, (req, res) => {
      res.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
      });
      res.end(html);
    });

    server.listen(443, '127.0.0.1', () => {
      console.log('SECUREOS_UI_SERVER_OK https://localhost');
    });
  '';
in {
  imports = [
    ./milestone1.nix
  ];

  networking.hostName = "secureos-browser";

  users.users.demo = {
    isNormalUser = true;
    initialPassword = "demo";
    extraGroups = [ "wheel" ];
  };

  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "modesetting" ];
  services.xserver.displayManager.startx.enable = true;
  services.xserver.desktopManager.xterm.enable = false;

  environment.systemPackages = with pkgs; [
    curl
    firefox
    matchbox
    nodejs
    xorg.xinit
    xdotool
  ];

  security.pki.certificates = [
    (builtins.readFile "${secureosLocalhostTls}/ca.crt")
  ];

  services.getty.autologinUser = lib.mkForce "demo";

  systemd.services.secureos-ui = {
    description = "SecureOS local HTTPS UI";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.nodejs}/bin/node ${secureosUiServer}";
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  environment.loginShellInit = ''
    if [ -z "''${DISPLAY:-}" ] && [ "''${XDG_VTNR:-}" = "1" ]; then
      exec startx
    fi
  '';

  users.users.demo.home = "/home/demo";

  system.activationScripts.milestone2DemoSession = ''
    mkdir -p /home/demo
    mkdir -p /home/demo/.mozilla/firefox/secureos.default
    cat > /home/demo/.mozilla/firefox/profiles.ini <<'EOF'
    [Profile0]
    Name=default
    IsRelative=1
    Path=secureos.default
    Default=1

    [General]
    StartWithLastProfile=1
    Version=2
    EOF
    cat > /home/demo/.mozilla/firefox/secureos.default/user.js <<'EOF'
    user_pref("browser.tabs.inTitlebar", 1);
    user_pref("browser.tabs.drawInTitlebar", true);
    user_pref("browser.tabs.closeWindowWithLastTab", false);
    user_pref("browser.startup.homepage", "https://localhost");
    user_pref("browser.startup.page", 1);
    user_pref("browser.toolbars.bookmarks.visibility", "never");
    user_pref("security.enterprise_roots.enabled", true);
    EOF
    cat > /home/demo/.xinitrc <<'EOF'
    xsetroot -solid "#0f172a"
    matchbox-window-manager -use_titlebar no -use_cursor yes &
    for _ in $(seq 1 40); do
      if curl --silent --fail --cacert ${secureosLocalhostTls}/ca.crt https://localhost/ >/dev/null; then
        break
      fi
      sleep 0.25
    done
    firefox --no-remote --profile /home/demo/.mozilla/firefox/secureos.default --new-window https://localhost &
    for _ in $(seq 1 40); do
      window_id="$(xdotool search --onlyvisible --class firefox 2>/dev/null | head -n 1 || true)"
      if [ -n "$window_id" ]; then
        xdotool windowmove "$window_id" 0 0
        xdotool windowsize "$window_id" 100% 100%
        xdotool key --window "$window_id" alt+F10
        break
      fi
      sleep 0.25
    done
    wait
    EOF
    chown -R demo:users /home/demo/.mozilla
    chown demo:users /home/demo/.xinitrc
    chmod 0755 /home/demo/.mozilla /home/demo/.mozilla/firefox /home/demo/.mozilla/firefox/secureos.default
    chmod 0644 /home/demo/.mozilla/firefox/profiles.ini
    chmod 0644 /home/demo/.mozilla/firefox/secureos.default/user.js
    chmod 0644 /home/demo/.xinitrc
  '';
}
