#!/bin/bash
# T-a (TYPES-1, bodies). bash tests/s3/types/ta.sh <s3c> (run from the repo root)
#  1. Y1 (31 files): `s3c --types` types every def body. Y1 compiles under s2c, so the true counts are: mismatches=0, untypednodes=0,
#     and every checked body fully typed (a body with an untyped node is not fully typed). bar: checked >= 2000.
#  2. armed: tests/s3/types/bad1.srs has exactly 3 mismatches (a Bool for an I64, an I64 for a Str, an if whose branches differ):
#     the checker must report mismatches=3 there. A checker that reports nothing passes 1 and fails 2.
#  mutants (measured by hand on a copy, not run here: each needs a rebuild): int literal kind I64 -> U32: mismatches 0 -> 2521;
#     no instantiation of generic params: 0 -> 16036.
. tests/s3/lib.sh
init T-a "$1"
num() { printf '%s\n' "$1" | sed -n "s/.* $2=\([0-9]*\).*/\1/p" | head -1; }

# 1. Y1
out=$(timeout 60 "$BIN" --types $Y1)
line=$(printf '%s\n' "$out" | grep '^bodies:' | head -1)
echo "Y1: $line" | cut -c1-200
chk=$(num "$line" checked); full=$(num "$line" fullytyped); mis=$(num "$line" mismatches); un=$(num "$line" untypednodes)
[ -n "$chk" ] && [ -n "$full" ] && [ -n "$mis" ] && [ -n "$un" ] || bad "no bodies line"
[ "${chk:-0}" -ge 2000 ] || bad "checked=$chk (want >= 2000)"
[ "${mis:-1}" = 0 ] || bad "Y1 mismatches=$mis (want 0)"
[ "${un:-1}" = 0 ] || bad "Y1 untypednodes=$un (want 0)"
[ "${full:-0}" = "${chk:-1}" ] || bad "fully typed $full of $chk"
printf '%s\n' "$out" | grep -E '^(mismatch|untyped) ' | head -10

# 2. armed
neg=$(timeout 20 "$BIN" --types lib/prelude.srs tests/s3/types/bad1.srs | grep '^bodies:' | head -1)
nm=$(num "$neg" mismatches)
echo "armed (bad1.srs): mismatches=$nm (want 3)"
[ "$nm" = 3 ] || bad "not armed: bad1.srs mismatches=$nm (want 3)"

# 3. handler fn bodies (emitted code) and clauses: their own rows. Y1 has 47 handler fns and no clause.
hl=$(printf '%s\n' "$out" | grep '^handlerbodies:' | head -1)
echo "Y1: $hl"
hc=$(num "$hl" checked); hu=$(num "$hl" untyped); hm=$(num "$hl" mismatches)
[ "${hc:-0}" -ge 40 ] || bad "handlerbodies checked=$hc (want >= 40)"
[ "${hu:-1}" = 0 ] || bad "handlerbodies untyped=$hu (want 0)"
[ "${hm:-1}" = 0 ] || bad "handlerbodies mismatches=$hm (want 0)"
cl=$(timeout 20 "$BIN" --types lib/prelude.srs tests/s3/types/clause.srs | grep '^clauses:' | head -1)
echo "clause.srs: $cl (want checked=7 untyped=0 mismatches=1)"
[ "$(num "$cl" checked)" = 7 ] && [ "$(num "$cl" untyped)" = 0 ] && [ "$(num "$cl" mismatches)" = 1 ] || bad "clause.srs: $cl"

# 4. check mode: want.srs types its if / match arms only through the pushed want (U32 literal arms): no mismatch, no annotate, fully typed.
#    mutant (measured by hand: Tp.resultOf := Tp.fresh): mismatches 0 -> 2 on want.srs, 0 -> 3 on Y1.
wb=$(timeout 20 "$BIN" --types lib/prelude.srs tests/s3/types/want.srs)
wl=$(printf '%s\n' "$wb" | grep '^bodies:' | head -1); wd=$(printf '%s\n' "$wb" | grep '^diags:' | head -1)
echo "want.srs: $(printf '%s' "$wl" | cut -c1-70) | $wd"
[ "$(num "$wl" mismatches)" = 0 ] || bad "want.srs mismatches=$(num "$wl" mismatches) (want 0: the want push is lost)"
[ "$(num "$wl" untypednodes)" = 0 ] || bad "want.srs untypednodes=$(num "$wl" untypednodes)"
[ "$(num "$wd" annotate)" = 0 ] || bad "want.srs annotate=$(num "$wd" annotate) (want 0)"
# 5. no defaulting (Q12): an unsolved var at the end of a def is an annotate Diag. want_neg.srs: exactly one, at line 7 (line 10 is solved by its sibling arm).
#    mutant (measured by hand: Tp.unsolved made `()`, a silent default): annotate 1 -> 0 here, so this step fails.
wn=$(timeout 20 "$BIN" --types lib/prelude.srs tests/s3/types/want_neg.srs)
wa=$(num "$(printf '%s\n' "$wn" | grep '^diags:')" annotate); wal=$(printf '%s\n' "$wn" | awk '$1=="annotate"{split($2,a,":"); print a[2]}' | tr '\n' ' ')
echo "want_neg.srs: annotate=$wa at lines [$wal] (want 1 at [7 ])"
[ "$wa" = 1 ] && [ "$wal" = "7 " ] || bad "want_neg.srs annotate=$wa lines=[$wal] (want 1 at line 7: an unsolved var must be rejected, never defaulted)"
echo "T-a: mismatches=$mis untyped=$un fullytyped=$full/$chk"
NAME="T-a Y1 bodies=$full/$chk handlerbodies=$hc"
finish
