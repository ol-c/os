{ modulesPath, ... }:

{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  system.stateVersion = "24.11";

  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  boot.kernelParams = [
    "console=ttyS0,115200n8"
  ];

  networking.hostName = "ol-c-browser";
}
