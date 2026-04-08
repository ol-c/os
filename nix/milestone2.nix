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
  };

  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "modesetting" ];
  services.xserver.displayManager.startx.enable = true;
  services.xserver.desktopManager.xterm.enable = false;

  environment.systemPackages = with pkgs; [
    firefox
    matchbox
    xorg.xinit
    xdotool
  ];

  services.getty.autologinUser = lib.mkForce "demo";

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
    user_pref("browser.toolbars.bookmarks.visibility", "never");
    EOF
    cat > /home/demo/.xinitrc <<'EOF'
    xsetroot -solid "#0f172a"
    matchbox-window-manager -use_titlebar no -use_cursor yes &
    firefox --no-remote --profile /home/demo/.mozilla/firefox/secureos.default --new-window about:home &
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
