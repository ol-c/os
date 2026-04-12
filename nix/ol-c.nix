{ ... }:

{
  imports = [
    ./modules/base.nix
    ./modules/users.nix
    ./modules/packages.nix
    ./modules/localhost-ui.nix
    ./modules/graphical-session.nix
  ];
}
