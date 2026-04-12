{
  description = "OL-C browser-first OS prototype";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixos-generators, ... }:
    let
      system = "x86_64-linux";
      firefoxLocalhostPatch = ./patches/firefox/0001-close-last-tab-to-localhost.patch;
      firefoxOverlay = final: prev: {
        "firefox-unwrapped" = prev."firefox-unwrapped".overrideAttrs (old: {
          patches = (old.patches or []) ++ [ firefoxLocalhostPatch ];
        });
      };
      firefoxPkgs = import nixpkgs {
        inherit system;
        overlays = [ firefoxOverlay ];
      };
      overlayModule = {
        nixpkgs.overlays = [ firefoxOverlay ];
      };
      olcModule = ./nix/ol-c.nix;
    in {
      overlays.default = firefoxOverlay;

      nixosConfigurations."ol-c" = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ overlayModule olcModule ];
      };

      packages.${system} = {
        firefox-localhost = firefoxPkgs.firefox;

        "ol-c-image" = nixos-generators.nixosGenerate {
          inherit system;
          format = "qcow";
          pkgs = firefoxPkgs;
          modules = [ olcModule ];
        };
      };
    };
}
