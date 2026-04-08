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
      xdotool
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

  users.users.demo.home = "/home/demo";

  system.activationScripts.milestone2DemoSession = ''
    mkdir -p /home/demo
    cat > /home/demo/.xinitrc <<'EOF'
    xsetroot -solid "#0f172a"
    openbox-session &
    firefox --new-window about:home &
    for _ in $(seq 1 40); do
      window_id="$(xdotool search --onlyvisible --class firefox 2>/dev/null | head -n 1 || true)"
      if [ -n "$window_id" ]; then
        xdotool windowactivate "$window_id"
        xdotool key --window "$window_id" alt+F10
        break
      fi
      sleep 0.25
    done
    wait
    EOF
    chown demo:users /home/demo/.xinitrc
    chmod 0644 /home/demo/.xinitrc
  '';
}
