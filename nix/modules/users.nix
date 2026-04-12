{ lib, ... }:

{
  users.users.root.initialPassword = "root";

  users.users.demo = {
    isNormalUser = true;
    initialPassword = "demo";
    extraGroups = [ "wheel" ];
    home = "/home/demo";
  };

  services.getty.autologinUser = lib.mkForce "demo";

  programs.bash.promptInit = ''
    PS1='[\u@\h:\w]\$ '
  '';
}
