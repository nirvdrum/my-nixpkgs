{
  description = "Personal Nix packages";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in
  {
    packages.${system} = {
      freecad-weekly = pkgs.callPackage ./pkgs/freecad-weekly { };
      default = self.packages.${system}.freecad-weekly;
    };
  };
}
