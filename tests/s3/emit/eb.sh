#!/bin/bash
# E-b (EMIT-1 behaviour): bash tests/s3/emit/eb.sh <s3c> (from the repo root). Each prog of tests/s3/emit/progs.txt is emitted by s3c, built with
# zig cc -O0 -fsanitize=address,undefined + rt/srs_rt.c (+ the prog's `// c:` args), run with its `// env:` variables; exit 0 and stdout ==
# tests/s2/prog/NAME.out (as tests/run.sh t_prog compares). `emit-b N/78`, the first failures with a diff head. bar: 78/78.
# EB_ONLY=name runs one prog; EB_SKIP_BUILD_CHECK is not a thing: a prog whose emit fails is a failure.
. tests/s3/lib.sh
init E-b "$1"
S2LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s2/prog/list.lib tests/s2/prog/file.lib"
sha256sum -c --status tests/s3/emit/rt.sha256 2>/dev/null || bad "rt/srs_rt.c changed"
W=$(mktemp -d "$HOME/.cache/srs3/eb.XXXXXX"); trap 'rm -rf "$T" "$W"' EXIT
ok=0; tot=0; fails=""
while read -r n; do
  [ -z "${EB_ONLY:-}" ] || [ "$EB_ONLY" = "$n" ] || continue
  tot=$((tot + 1)); why=""; src="tests/s2/prog/$n.srs"
  timeout 20 "$BIN" --emit $S2LIBS "$src" > "$W/p.c" 2> "$W/e.txt" || why="emit: $(grep -m1 . "$W/e.txt" | cut -c1-120)"
  if [ -z "$why" ]; then
    timeout 120 zig cc -std=gnu11 -O0 -fsanitize=address,undefined -w -o "$W/p.bin" "$W/p.c" rt/srs_rt.c $(sed -n 's|^// c: ||p' "$src") 2> "$W/b.txt" || why="build: $(grep -m1 -E 'error|undefined' "$W/b.txt" | cut -c1-120)"
  fi
  if [ -z "$why" ]; then
    out=$(env $(sed -n 's|^// env: ||p' "$src") timeout 20 "$W/p.bin" 2> "$W/r.txt"); rc=$?
    if [ $rc != 0 ]; then why="run exit=$rc $(grep -m1 -E 'ERROR|runtime error|srs:' "$W/r.txt" | cut -c1-120)"
    elif [ "$out" != "$(cat "tests/s2/prog/$n.out")" ]; then
      printf '%s\n' "$out" > "$W/o.txt"; why="stdout differs: $(diff "$W/o.txt" "tests/s2/prog/$n.out" | head -3 | tr '\n' '|' | cut -c1-150)"
    fi
  fi
  if [ -z "$why" ]; then ok=$((ok + 1)); else fails="$fails$n: $why"$'\n'; fi
done < tests/s3/emit/progs.txt
echo "emit-b $ok/$tot"
printf '%s' "$fails" | head -${EB_SHOW:-12}
[ -n "${EB_ONLY:-}" ] || [ "$tot" = 78 ] || bad "progs.txt has $tot entries (want 78)"
[ "$ok" = "$tot" ] || bad "emit-b $ok/$tot (bar 78/78)"
finish
