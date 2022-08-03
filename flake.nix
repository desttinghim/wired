{
  description = "A very basic flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:arqv/zig-overlay";
    unstable.url = "nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, zig, flake-utils, unstable }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        upkgs = unstable.legacyPackages.${system};
      in
      {

        # nix develop
        devShells.default = pkgs.mkShell {
          buildInputs = [
            zig.packages.${system}.master.latest
            pkgs.butler
            pkgs.binaryen
            pkgs.tiled
            pkgs.libresprite
            upkgs.ldtk
          ];
        };

      });
}
