{
  description = "Hatchet (hatchet-lite) built from source — Go binaries + dashboard";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in
    {
      packages = forAllSystems (pkgs: rec {
        hatchet-lite = pkgs.callPackage ./package.nix { };
        # Same build as the published *-dev images: dashboard/REST auth disabled.
        hatchet-lite-dev = pkgs.callPackage ./package.nix {
          buildTags = [ "authdisabled" ];
        };
        default = hatchet-lite;
      });

      overlays.default = final: prev: {
        hatchet-lite = final.callPackage ./package.nix { };
        hatchet-lite-dev = final.callPackage ./package.nix {
          buildTags = [ "authdisabled" ];
        };
      };

      checks = forAllSystems (pkgs: {
        version =
          pkgs.runCommand "hatchet-lite-version-check"
            {
              nativeBuildInputs = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
            }
            ''
              test "$(hatchet-lite --version)" = "${
                self.packages.${pkgs.stdenv.hostPlatform.system}.default.version
              }"
              touch $out
            '';

        assets = pkgs.runCommand "hatchet-lite-assets-check" { } ''
          test -f ${
            self.packages.${pkgs.stdenv.hostPlatform.system}.default
          }/share/hatchet/static-assets/index.html
          test -f ${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/entrypoint.sh
          touch $out
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            self.packages.${pkgs.stdenv.hostPlatform.system}.default
            pkgs.postgresql_17
            pkgs.process-compose
            pkgs.curl
            pkgs.jq
          ];
          shellHook = ''
            echo "hatchet-lite $(hatchet-lite --version)"
            echo "  postgres:        $(postgres --version)"
            echo "  process-compose: $(process-compose version 2>/dev/null | head -1)"
            echo
            echo "See example/process-compose.yaml for a local Postgres + hatchet-lite stack."
          '';
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
