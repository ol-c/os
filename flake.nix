{
  description = "Secure browser-first OS prototype";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-generators.url = "github:nix-community/nixos-generators";
  };

  outputs = inputs@{ self, nixpkgs, nixos-generators, ... }:
    let
      system = "x86_64-linux";
      milestone1Module = ./nix/milestone1.nix;
      milestone2Module = ./nix/milestone2.nix;
    in {
      nixosConfigurations.milestone1 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ milestone1Module ];
      };

      nixosConfigurations.milestone2 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [ milestone2Module ];
      };

      packages.${system} = {
        milestone1-image = nixos-generators.nixosGenerate {
          inherit system;
          format = "qcow";
          modules = [ milestone1Module ];
        };

        milestone2-image = nixos-generators.nixosGenerate {
          inherit system;
          format = "qcow";
          modules = [ milestone2Module ];
        };
      };
    };
}
