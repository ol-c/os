{ lib, pkgs, ... }:

{
  imports = [
    ./milestone1.nix
  ];

  networking.hostName = "secureos-browser";

  users.users.demo = {
    isNormalUser = true;
    initialPassword = "demo";
    extraGroups = [ "wheel" ];
    packages = with pkgs; [
      firefox
      openbox
      xorg.xinit
    ];
  };

  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "modesetting" ];
  services.xserver.displayManager.startx.enable = true;
  services.xserver.desktopManager.xterm.enable = false;
  services.xserver.windowManager.openbox.enable = true;

  environment.systemPackages = with pkgs; [
    firefox
    openbox
    xorg.xinit
    xdotool
  ];

  services.getty.autologinUser = lib.mkForce "demo";

  environment.loginShellInit = ''
    if [ -z "''${DISPLAY:-}" ] && [ "''${XDG_VTNR:-}" = "1" ]; then
      exec startx
    fi
  '';

  environment.etc."secureos/milestone2.html".text = ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>SecureOS Milestone 2</title>
        <style>
          :root {
            color-scheme: dark;
            --bg: #0f172a;
            --panel: #162033;
            --accent: #f59e0b;
            --text: #e5eef9;
            --muted: #9fb3c8;
          }
          * { box-sizing: border-box; }
          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            font-family: "Iosevka Aile", "IBM Plex Sans", sans-serif;
            background:
              radial-gradient(circle at top, rgba(245, 158, 11, 0.22), transparent 35%),
              linear-gradient(180deg, #111827, var(--bg));
            color: var(--text);
          }
          main {
            width: min(920px, calc(100vw - 64px));
            padding: 48px;
            border: 1px solid rgba(255,255,255,0.08);
            border-radius: 24px;
            background: rgba(22, 32, 51, 0.88);
            box-shadow: 0 24px 90px rgba(0,0,0,0.35);
          }
          h1 {
            margin: 0 0 16px;
            font-size: clamp(2rem, 4vw, 4rem);
            line-height: 1;
            letter-spacing: -0.04em;
          }
          p {
            margin: 0 0 16px;
            font-size: 1.1rem;
            line-height: 1.6;
            color: var(--muted);
          }
          code {
            color: var(--accent);
            font-size: 0.95em;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>SecureOS Browser Milestone</h1>
          <p>An actual graphical browser is running inside the VM.</p>
          <p>If you can see this page inside Firefox, Milestone 2 is working.</p>
          <p><code>MILESTONE2_BROWSER_OK</code></p>
        </main>
      </body>
    </html>
  '';

  users.users.demo.home = "/home/demo";

  system.activationScripts.milestone2DemoSession = ''
    mkdir -p /home/demo
    cat > /home/demo/.xinitrc <<'EOF'
    xsetroot -solid "#0f172a"
    openbox-session &
    firefox --kiosk file:///etc/secureos/milestone2.html
    EOF
    chown demo:users /home/demo/.xinitrc
    chmod 0644 /home/demo/.xinitrc
  '';
}
