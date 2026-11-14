#!/bin/bash
# E-a (EMIT-1): bash tests/s3/emit/ea.sh <s3c> (from the repo root). For each of the 81 progs of tests/s3/emit/progs.txt:
#  s3c --emit $S2LIBS tests/s2/prog/NAME.srs > p.c (exit 0), then tcc -c and `zig cc -std=c11 -Werror -c` with 0 diagnostics.
# (zig cc -fsyntax-only cannot run here: it fails to rename its .o; -c has the same frontend diagnostics.)
# `emit-a N/81`; a failing prog is listed with its first diagnostic. bar: 81/81. EA_ONLY=name runs one prog.
. tests/s3/lib.sh
init E-a "$1"
TCC=${TCC:-/nix/store/kz7m0d6n0n050gh6k9vq1rh8jdmdfj25-tcc-0.9.27-unstable-2026-09-22/bin/tcc}
[ -x "$TCC" ] || bad "no tcc at $TCC"
S2LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s2/prog/list.lib tests/s2/prog/file.lib"
W=$(mktemp -d "$HOME/.cache/srs3/ea.XXXXXX"); trap 'rm -rf "$T" "$W"' EXIT
ok=0; tot=0; fails=""
while read -r n; do
  [ -z "${EA_ONLY:-}" ] || [ "$EA_ONLY" = "$n" ] || continue
  tot=$((tot + 1)); why=""
  timeout 20 "$BIN" --emit $S2LIBS "tests/s2/prog/$n.srs" > "$W/p.c" 2> "$W/e.txt"; rc=$?
  if [ $rc != 0 ]; then why="emit exit=$rc $(grep -m1 . "$W/e.txt" | cut -c1-150)"
  else
    timeout 60 "$TCC" -c -o "$W/p.o" "$W/p.c" 2> "$W/t.txt" || why="tcc: $(grep -m1 . "$W/t.txt" | cut -c1-150)"
    [ -s "$W/t.txt" ] && [ -z "$why" ] && why="tcc diag: $(grep -m1 . "$W/t.txt" | cut -c1-150)"
    if [ -z "$why" ]; then
      timeout 60 zig cc -std=c11 -Werror -Wno-unused-command-line-argument -c -o "$W/p.zo" "$W/p.c" 2> "$W/z.txt" || why="zig: $(grep -m1 -E 'error|warning' "$W/z.txt" | cut -c1-150)"
    fi
  fi
  if [ -z "$why" ]; then ok=$((ok + 1)); else fails="$fails$n: $why"$'\n'; fi
done < tests/s3/emit/progs.txt
echo "emit-a $ok/$tot"
printf '%s' "$fails" | head -${EA_SHOW:-12}
[ -n "${EA_ONLY:-}" ] || [ "$tot" = 81 ] || bad "progs.txt has $tot entries (want 81)"
[ "$ok" = "$tot" ] || bad "emit-a $ok/$tot (bar 81/81)"
finish
