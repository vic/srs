# The repo: one root scope. Its sinks become flake outputs: devShells (commands), write-files + checks (files).
{
  yen,
  lib,
  inputs,
  ...
}:
let
  inherit (yen.lib.batteries) files devshell;
in
{
  yen.kinds.repo.spawns = { }; # a kind with `spawns` and no parent is a root scope (yen lib/_eval/tree.nix)
  yen.kinds.repo.sinks = {
    out.reduce = yen.lib.reduce.merge;
    files.out = files.writer {
      from = yen.kinds.repo.sinks.files;
      inherit (inputs) files;
      inherit lib;
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
      root = inputs.self;
    };
    # each aspect gives a list of commands; the shell menu shows them
    commands.out = devshell.numtide {
      from = yen.kinds.repo.sinks.commands;
      inherit (inputs) devshell;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      pkgsOf = system: inputs.nixpkgs.legacyPackages.${system};
      name = "srs";
      packages = pkgs: [
        pkgs.zig # S0 compiler + C compiler/linker (C3, C4)
        pkgs.lean4 # lean-check: the soundness proofs of the effect checker (C10)
        pkgs.coreutils # timeout in tests/run.sh
        pkgs.git
        pkgs.nixfmt
        pkgs.actionlint
        pkgs.shellcheck
        pkgs.hyperfine # srs-bench: the speed oracle (vic 2026-11-05)
        pkgs.jq # srs-bench: reads the hyperfine json
      ]
      # perf record: where the time goes
      ++ pkgs.lib.optional pkgs.stdenv.isLinux pkgs.perf;
    };
  };
  yen.repo.srs = { };
  yen.flake = { out, ... }: out;
}
