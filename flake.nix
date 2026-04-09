{
  description = "Secure browser-first OS prototype";

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
      milestone1Module = ./nix/milestone1.nix;
      milestone2Module = ./nix/milestone2.nix;
    in {
      overlays.default = firefoxOverlay;

      nixosConfigurations.milestone1 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ overlayModule milestone1Module ];
      };

      nixosConfigurations.milestone2 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ overlayModule milestone2Module ];
      };

      packages.${system} = {
        firefox-localhost = firefoxPkgs.firefox;

        milestone1-image = nixos-generators.nixosGenerate {
          inherit system;
          format = "qcow";
          pkgs = firefoxPkgs;
          modules = [ milestone1Module ];
        };

        milestone2-image = nixos-generators.nixosGenerate {
          inherit system;
          format = "qcow";
          pkgs = firefoxPkgs;
          modules = [ milestone2Module ];
        };
      };
    };
}
