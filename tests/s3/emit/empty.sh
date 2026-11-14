#!/bin/bash
# empty (PERF-1): bash tests/s3/emit/empty.sh <s3c> (from the repo root). `s3c --emit` with NO file arguments prints the same stdout bytes and
# exits with the same code as the reference build (REF, default $HOME/.cache/srs3/perf1/bin2z_ref, the s3c before the chunk output): an empty file
# list still has the preamble, the main stub and the rest. Armed: a one-file run must differ from the empty one (the compare can tell them apart),
# and a forced failure line shows the script can fail.
. tests/s3/lib.sh
init empty "$1"
REF=${REF:-$HOME/.cache/srs3/perf1/bin2z_ref}
[ -x "$REF" ] || bad "no reference s3c at $REF"
timeout 20 "$REF" --emit > "$T/ref.c" 2> /dev/null; rr=$?
timeout 20 "$BIN" --emit > "$T/new.c" 2> /dev/null; rn=$?
[ -s "$T/ref.c" ] || bad "the reference printed nothing for no files"
cmp -s "$T/ref.c" "$T/new.c" || bad "stdout differs from the reference for no files ($(wc -c < "$T/ref.c") vs $(wc -c < "$T/new.c") bytes)"
[ "$rr" = "$rn" ] || bad "exit $rn, the reference exits $rr"
# arming: one file gives other bytes than none
timeout 20 "$BIN" --emit lib/prelude.srs > "$T/one.c" 2> /dev/null
cmp -s "$T/new.c" "$T/one.c" && bad "armed compare: a one-file run equals the empty run"
# forced failure: the compare must fail on a mutated copy
cp "$T/ref.c" "$T/mut.c"; printf 'x' >> "$T/mut.c"
cmp -s "$T/ref.c" "$T/mut.c" && bad "forced failure line did not fail"
finish
