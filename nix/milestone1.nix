{ modulesPath, lib, pkgs, ... }:

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

  services.getty.autologinUser = lib.mkDefault "root";

  users.users.root.initialPassword = "root";

  environment.systemPackages = with pkgs; [
    bash
    coreutils
  ];

  systemd.services.milestone1-boot-ok = {
    description = "Milestone 1 boot success marker";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/ttyS0";
    };
    script = ''
      echo "MILESTONE1_BOOT_OK"
    '';
  };
}
