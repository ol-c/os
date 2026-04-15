{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    bash
    coreutils
    curl
    firefox
    git
    matchbox
    nodejs
    openssh
    pulseaudio
    ripgrep
    spice-vdagent
    ttyd
    wireplumber
    xorg.xinit
    xdotool
  ];
}
