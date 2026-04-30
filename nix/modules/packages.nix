{ pkgs, ... }:

{
  fonts.enableDefaultPackages = false;
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "Noto Sans"
      "Noto Sans CJK SC"
      "Noto Sans CJK TC"
      "Noto Sans CJK HK"
      "Noto Sans CJK JP"
      "Noto Sans CJK KR"
      "Noto Color Emoji"
    ];
    serif = [
      "Noto Serif"
      "Noto Serif CJK SC"
      "Noto Serif CJK TC"
      "Noto Serif CJK HK"
      "Noto Serif CJK JP"
      "Noto Serif CJK KR"
      "Noto Color Emoji"
    ];
    monospace = [
      "Noto Sans Mono"
      "Noto Sans CJK SC"
      "Noto Sans CJK TC"
      "Noto Sans CJK HK"
      "Noto Sans CJK JP"
      "Noto Sans CJK KR"
      "Noto Color Emoji"
    ];
    emoji = [
      "Noto Color Emoji"
    ];
  };

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
