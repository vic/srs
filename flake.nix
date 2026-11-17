# srs: the s4 kernel built from its seed. bootstrap/srs_seed.c is the C the image emits for itself
# (fixpoint: the kernel built from it emits it again byte for byte); bootstrap/srs_rt.c is the runtime.
# The image source is ./srs (one unit per file); `nix build` gives bin/srs.
{
  description = "srs: the s4 kernel, built from its self-emitted seed";

  inputs.nixpkgs.url = "https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      each = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = each (pkgs: rec {
        srs = pkgs.stdenv.mkDerivation {
          pname = "srs";
          version = "0";
          src = ./bootstrap;
          dontConfigure = true;
          # -O1: measured 9.7 s build and 0.09 s per check (vic/prompt.md 7.1)
          buildPhase = ''
            runHook preBuild
            $CC -std=gnu11 -O1 -w -o srs srs_seed.c srs_rt.c -lm
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            install -Dm755 srs $out/bin/srs
            runHook postInstall
          '';
          meta.mainProgram = "srs";
        };
        default = srs;
      });

      # `nix develop`: the C compilers the kernel and its programs are built with, just (Justfile) and valgrind
      devShells = each (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.just
            pkgs.gcc # the kernel: gcc -O1 (9.7 s build, 0.09 s per check)
            pkgs.tinycc # small programs: 0.1 s builds
            pkgs.valgrind
          ];
        };
      });
    };
}
