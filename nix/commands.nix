# The devshell commands. Every command runs from the repo root, whatever the directory.
# CI runs these commands and nothing else (ci.nix), so every CI step runs the same way locally.
{ yen, ... }:
let
  cmd = category: name: help: command: {
    inherit category name help;
    command = "set -eu; cd \"$(git rev-parse --show-toplevel)\"; ${command}";
  };
  # the build dir of tests/run.sh
  build = ''B=''${B:-''${XDG_RUNTIME_DIR:-/tmp}/srs-build}; mkdir -p "$B"'';
  cc = "zig cc -std=gnu11 -O1 -w";
in
{
  yen.aspects.srs-commands = {
    at = yen.kinds.repo;
    commands = [
      (cmd "srs" "srs-build" "build the srs compiler from bootstrap/seed.c to $B/srs" ''
        ${build}
        ${cc} -o "$B/srs" bootstrap/seed.c rt/srs_rt.c
        echo "$B/srs"
      '')
      (cmd "srs" "srs-run"
        "srs-run [LIB...] FILE.srs [-- ARGS]: compile with the prelude, then run (srs-build first)"
        ''
          ${build}
          srcs=(); while [ $# -gt 0 ] && [ "$1" != -- ]; do srcs+=("$1"); shift; done
          [ $# -gt 0 ] && shift
          [ ''${#srcs[@]} -gt 0 ] || { echo "usage: srs-run [LIB...] FILE.srs [-- ARGS]" >&2; exit 1; }
          test -x "$B/srs" || srs-build >/dev/null
          n=$(basename "''${srcs[-1]}" .srs)
          "$B/srs" lib/prelude.srs "''${srcs[@]}" > "$B/$n.c"
          ${cc} -o "$B/$n" "$B/$n.c" rt/srs_rt.c
          "$B/$n" "$@"
        ''
      )
      (cmd "srs" "seed-update"
        "after an S1 change: bootstrap/seed.c = the S1 self-compile of the last srs-test"
        ''${build}; cp "$B/s2.c" bootstrap/seed.c''
      )
      (cmd "test" "srs-test" "the gate: S0 -> S1 -> fixpoint, seed, pass and neg programs"
        "./tests/run.sh"
      )
      (cmd "test" "s0-test" "the S0 zig unit tests" "timeout 120 zig test s0/main.zig")
      (cmd "fmt" "fmt" "format every tracked nix file (nixfmt)"
        "git ls-files -z '*.nix' | xargs -0 nixfmt"
      )
      (cmd "fmt" "fmt-check" "every tracked nix file is formatted (nixfmt), as CI checks"
        "git ls-files -z '*.nix' | timeout 60 xargs -0 nixfmt --check"
      )
      (cmd "fmt" "lint" "the workflows are valid (actionlint, with shellcheck)"
        "actionlint .github/workflows/*.yml"
      )
      (cmd "ci" "write-files" "write the generated files (.github/workflows/ci.yml)"
        "nix run .#write-files"
      )
      (cmd "ci" "ci" "run the CI jobs locally, in order"
        ''for c in fmt-check lint s0-test srs-test; do echo "== $c"; $c; done''
      )
    ];
  };
}
