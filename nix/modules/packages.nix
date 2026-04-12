{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    bash
    coreutils
    curl
    firefox
    matchbox
    nodejs
    spice-vdagent
    ttyd
    xorg.xinit
    xdotool
  ];
}
