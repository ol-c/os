{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    bash
    coreutils
    curl
    firefox
    matchbox
    nodejs
    pulseaudio
    spice-vdagent
    ttyd
    wireplumber
    xorg.xinit
    xdotool
  ];
}
