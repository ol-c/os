{ pkgs, ... }:

{
  fonts.packages = with pkgs; [
    dejavu_fonts
    inconsolata
  ];

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
