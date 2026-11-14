#!/bin/bash
# fixpoint (FIXPOINT 1): bash tests/s3/emit/fixpoint.sh <s3c> (from the repo root). The s3c binary BIN (built by s2c) emits the C of the 13 s3c
# source files (C2); zig -O1 builds C2 into BIN2; BIN2 emits the same files again (C3). C2 and C3 must be byte-identical: s3c compiles itself on
# the subset, with no checks (s2c stays the acceptance gate for every s3c source commit). Armed: a copy of s3/main.srs with one changed character
# must give other C (the compare can tell two sources apart), and a forced failure line shows the script can fail.
. tests/s3/lib.sh
init fixpoint "$1"
S="lib/prelude.srs s2/sym.srs s2/coll.srs s2/bmap.srs s3/lex.srs s3/parse.srs s3/ast.srs s3/parse2.srs s3/print.srs s3/names.srs s3/types.srs s3/emit.srs s3/main.srs"
timeout 120 "$BIN" --emit $S > "$T/c2.c" 2> "$T/c2.err"; r=$?
[ "$r" = 0 ] && [ -s "$T/c2.c" ] || { bad "BIN --emit of the 13 s3c files: exit $r, $(wc -c < "$T/c2.c") bytes"; finish; }
timeout 300 zig cc -std=gnu11 -O1 -w -static -target x86_64-linux-musl -o "$T/bin2" "$T/c2.c" rt/srs_rt.c > "$T/zig.log" 2>&1 || { bad "zig cc of C2 failed: $(head -c 200 "$T/zig.log")"; finish; }
timeout 120 "$T/bin2" --emit $S > "$T/c3.c" 2> "$T/c3.err"; r=$?
[ "$r" = 0 ] || bad "bin2 --emit exit $r"
cmp -s "$T/c2.c" "$T/c3.c" || bad "C2 and C3 differ ($(wc -c < "$T/c2.c") vs $(wc -c < "$T/c3.c") bytes)"
# arming: one changed character in the source gives other C
sed 's/usage: s3c/usage: s3d/' s3/main.srs > "$T/main_mut.srs"
cmp -s s3/main.srs "$T/main_mut.srs" && bad "armed: the sed changed nothing"
S2=${S/s3\/main.srs/$T/main_mut.srs}
timeout 120 "$BIN" --emit $S2 > "$T/c2m.c" 2> /dev/null
cmp -s "$T/c2.c" "$T/c2m.c" && bad "armed compare: a one-character source change gives equal C"
# forced failure: the compare must fail on a mutated copy
cp "$T/c2.c" "$T/mut.c"; printf 'x' >> "$T/mut.c"
cmp -s "$T/c2.c" "$T/mut.c" && bad "forced failure line did not fail"
finish
