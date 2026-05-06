{ lib, pkgs, ... }:

{
  system.stateVersion = "25.11";
  ids.uids.nixbld = lib.mkForce 700;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.journald.extraConfig = ''
    Storage=persistent
  '';

  networking.hostName = "ol-c-browser";
  networking.networkmanager.enable = true;

  hardware.enableRedistributableFirmware = true;

  environment.systemPackages = [
    pkgs.networkmanager
  ];

  systemd.tmpfiles.rules = [
    "d /var/lib/ol-c 0755 root root -"
    "d /etc/ol-c 0755 root root -"
  ];
}
