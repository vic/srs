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
      (cmd "test" "srs-bench"
        "the speed oracle: hyperfine S1 self-compile, S1 Lean gen, all pass tests; fails when slower than bench/baseline.txt (srs-test first)"
        ''${build}; bash tests/bench.sh''
      )
      (cmd "test" "bench-update" "after a faster delivery: save this run as bench/baseline.txt"
        ''${build}; bash tests/bench.sh update''
      )
      (cmd "srs" "seed-update"
        "after an S1 change: bootstrap/seed.c = the S1 self-compile of the last srs-test"
        ''${build}; cp "$B/s2.c" bootstrap/seed.c''
      )
      (cmd "test" "srs-test" "the gate, self-hosted: seed -> S1 -> fixpoint, pass and neg programs"
        "./tests/run.sh"
      )
      (cmd "test" "lean-check"
        "Lean: Impl = s1/*.srs via s1 --lean (fresh, must match the committed file), Impl verdicts = S1, model soundness proof (no sorry)"
        ''
          ${build}
          ${cc} -o "$B/seed" bootstrap/seed.c rt/srs_rt.c
          S1SRC="lib/prelude.srs lib/datalog.srs s1/node.srs s1/lex.srs s1/parse.srs s1/check.srs s1/types.srs s1/given.srs s1/facts.srs s1/purity.srs s1/hash.srs s1/mono.srs s1/emit.srs s1/lean.srs s1/leanspec.srs"
          gen() { # gen NS OUT files...: generated Lean must match the committed file
            ns=$1; out=$2; shift 2
            timeout 10 "$B/seed" --lean "$ns" "$@" > "$B/gen.lean" || exit 1
            cmp -s "$B/gen.lean" "$out" || { cp "$B/gen.lean" "$out"; echo "$out was stale: regenerated, commit it" >&2; exit 1; }
          }
          gen Impl lean/Srs/Impl/S1.lean $S1SRC
          gen Contracts lean/Srs/Contracts.lean lib/prelude.srs tests/list.lib tests/contracts.srs
          gen Kanren lean/Srs/Kanren.lean lib/prelude.srs lib/kanren.srs
          gen Datalog lean/Srs/Datalog.lean lib/prelude.srs lib/datalog.srs
          echo "proof lean (debt): $(grep -cE '^ +proof lean' s1/*.srs lib/*.srs tests/*.srs | awk -F: '{s+=$2} END{print s}')"
          ! grep -rn --include='*.lean' -w -e sorry -e admit -e axiom lean/Srs || { echo "unproven step" >&2; exit 1; }
          # ImplRun reads tests/ by IO, which lake does not track: drop its outputs so the verdicts always run again
          rm -f lean/.lake/build/lib/lean/Srs/ImplRun.*
          cd lean && timeout 600 lake build
        ''
      )
      # bootstrap only when absolutely necessary (C10): the seed cannot build the S1 src
      (cmd "bootstrap" "s0-bootstrap" "S0 (zig) -> S1 -> bootstrap/seed.c, then srs-test" ''
        ${build}
        timeout 120 zig test s0/main.zig
        timeout 120 zig build-exe s0/main.zig -femit-bin="$B/s0"
        S1SRC="lib/prelude.srs lib/datalog.srs s1/node.srs s1/lex.srs s1/parse.srs s1/check.srs s1/types.srs s1/given.srs s1/facts.srs s1/purity.srs s1/hash.srs s1/mono.srs s1/emit.srs s1/lean.srs s1/main.srs"
        "$B/s0" $S1SRC > "$B/s1.c"
        ${cc} -o "$B/s1" "$B/s1.c" rt/srs_rt.c
        "$B/s1" $S1SRC > bootstrap/seed.c
        ./tests/run.sh
      '')
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
        ''for c in fmt-check lint srs-test lean-check; do echo "== $c"; $c; done''
      )
    ];
  };
}
