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
    novnc
    pulseaudio
    qemu_kvm
    ripgrep
    shadow
    spice-vdagent
    ttyd
    util-linux
    virtiofsd
    wireplumber
    xdg-utils
    xorg.xinit
    xdotool
  ];
}
