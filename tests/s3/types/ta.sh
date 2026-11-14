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
echo "T-a: mismatches=$mis untyped=$un fullytyped=$full/$chk"
finish
