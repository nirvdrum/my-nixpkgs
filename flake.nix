{
  description = "Personal Nix packages";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-darwin" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
  in
  {
    packages = forAllSystems (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        freecad-weekly = pkgs.callPackage ./pkgs/freecad-weekly { };
        msty-studio = pkgs.callPackage ./pkgs/msty-studio { };
        default = self.packages.${system}.freecad-weekly;
      });

    apps = forAllSystems (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        update-freecad-weekly = {
          type = "app";
          # Filters to weekly-YYYY.MM.DD tags only, so a stable 1.x release
          # landing on the GitHub releases page doesn't get picked up as an update.
          program = toString (pkgs.writeShellScript "update-freecad-weekly" ''
            exec ${pkgs.nix-update}/bin/nix-update --flake freecad-weekly --version-regex 'weekly-.*'
          '');
        };
      });
  };
}
