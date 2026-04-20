{
  description = "ol-c browser-first OS prototype";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      firefoxLocalhostPatch = ./patches/firefox/0001-close-last-tab-to-localhost.patch;
      firefoxSourceOverlay = final: prev: {
        "firefox-unwrapped" = prev."firefox-unwrapped".overrideAttrs (old: {
          patches = (old.patches or []) ++ [ firefoxLocalhostPatch ];
        });
        firefox = final.wrapFirefox final.firefox-unwrapped { };
      };
      firefoxFastOverlay = import ./nix/firefox-localhost-fast.nix {
        inherit firefoxLocalhostPatch;
      };
      basePkgs = import nixpkgs {
        inherit system;
      };
      firefoxPkgs = import nixpkgs {
        inherit system;
        overlays = [ firefoxFastOverlay ];
      };
      firefoxSourcePkgs = import nixpkgs {
        inherit system;
        overlays = [ firefoxSourceOverlay ];
      };
      overlayModule = {
        nixpkgs.overlays = [ firefoxFastOverlay ];
      };
      olcModule = ./nix/ol-c.nix;
    in {
      overlays.default = firefoxFastOverlay;
      overlays.source = firefoxSourceOverlay;

      nixosConfigurations."ol-c" = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ overlayModule olcModule ];
      };

      packages.${system} = {
        firefox-localhost = firefoxPkgs.firefox;
        firefox-localhost-source = firefoxSourcePkgs.firefox;
        novnc = basePkgs.novnc;
        "ol-c-image" = self.nixosConfigurations."ol-c".config.system.build.images.qemu;
      };
    };
}
