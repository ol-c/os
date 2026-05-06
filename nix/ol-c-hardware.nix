{ ... }:

{
  imports = [
    ./modules/hardware-base.nix
    ./modules/users.nix
    ./modules/packages.nix
    ./modules/localhost-ui.nix
    ./modules/graphical-session.nix
    ./modules/development.nix
  ];
}
