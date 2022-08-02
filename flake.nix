{
  description = "A very basic flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:arqv/zig-overlay";
  };

  outputs = { self, nixpkgs, zig, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {

        # nix develop
        devShells.default = pkgs.mkShell {
          buildInputs = [
            zig.packages.${system}.master.latest
            pkgs.butler
            pkgs.binaryen
            pkgs.tiled
          ];
        };

      });
}
