#!/bin/bash
# E-d (EMIT-1): bash tests/s3/emit/ed.sh <s3c> (from the repo root). `s3c --emit` on the 31 Y1 files (tests/s3/y1.sh) exits 0 with no named
# emit reason (unsupported=0 unsupportedResume=0 overflow=0 lateTypes=0), and the C compiles under tcc -c with 0 diagnostics (no stderr at all).
# The behaviour of that C is the fixpoint rung. Prints the C size and bytes per srs line.
. tests/s3/lib.sh
init E-d "$1"
TCC=${TCC:-/nix/store/kz7m0d6n0n050gh6k9vq1rh8jdmdfj25-tcc-0.9.27-unstable-2026-09-22/bin/tcc}
[ -x "$TCC" ] || bad "no tcc at $TCC"
W=$(mktemp -d "$HOME/.cache/srs3/ed.XXXXXX"); trap 'rm -rf "$T" "$W"' EXIT
timeout 60 "$BIN" --emit $Y1 > "$W/y1.c" 2> "$W/e.txt"; rc=$?
sum=$(grep -m1 '^emit:' "$W/e.txt")
echo "$sum" | cut -c1-300
[ "$rc" = 0 ] || bad "emit exit=$rc"
for r in unsupported unsupportedResume overflow lateTypes; do
  printf '%s\n' "$sum" | grep -q " $r=0" || bad "emit summary: $r is not 0"
done
bytes=$(wc -c < "$W/y1.c"); lines=$(cat $Y1 | wc -l)
echo "C bytes=$bytes srs lines=$lines bytes/line=$((bytes / lines))"
timeout 120 "$TCC" -c -o "$W/y1.o" "$W/y1.c" 2> "$W/t.txt" || bad "tcc failed: $(grep -m1 . "$W/t.txt" | cut -c1-150)"
[ ! -s "$W/t.txt" ] || bad "tcc diagnostics: $(wc -l < "$W/t.txt") lines, first: $(grep -m1 . "$W/t.txt" | cut -c1-150)"
finish
