#!/bin/bash
# T-b (TYPES-1, C prototypes). bash tests/s3/types/tb.sh <s3c> (run from the repo root)
#  reference = the one-line prototypes `static R f_Name(T p_x, ...);` of the C that `s2c --no-mem-optimization` emits for Y1
#  (tests/s3/types/ref-protos.txt, sorted; regenerated from $S2C when that binary is set, and then it must equal the stored file).
#  `s3c --types-dump Y1` prints the prototype of every non-generic def (2,258) and of every instance of a generic def (1,210: the mono
#  set of --types-mono, with the type params replaced by the instance args): 3,468 lines.
#  bar: every printed prototype is in the reference (equal == total), every reference prototype is printed (equal == reference),
#  total >= 3000. The first 10 diffs are shown. armed: one printed prototype is changed (its return type) and the comparison must miss it.
. tests/s3/lib.sh
init T-b "$1"
export LC_ALL=C
REF=tests/s3/types/ref-protos.txt
if [ -n "${S2C:-}" ] && [ -x "$S2C" ]; then
  timeout 120 "$S2C" --no-mem-optimization $Y1 2>/dev/null | grep '^static .* f_.*);$' | sort > "$T/fresh.txt"
  cmp -s "$T/fresh.txt" "$REF" || bad "stored reference differs from a fresh s2c run"
fi
timeout 60 "$BIN" --types-dump $Y1 | sort > "$T/mine.txt"
total=$(wc -l < "$T/mine.txt")
nref=$(wc -l < "$REF")
equal=$(comm -12 "$T/mine.txt" "$REF" | wc -l)
echo "T-b prototypes: equal=$equal total=$total reference=$nref"
comm -23 "$T/mine.txt" "$REF" | head -10 | cut -c1-220 | sed 's/^/  extra   /'
comm -13 "$T/mine.txt" "$REF" | head -10 | cut -c1-220 | sed 's/^/  missing /'
[ "$total" -ge 3000 ] && [ "$equal" = "$total" ] && [ "$equal" = "$nref" ] || bad "equal=$equal total=$total reference=$nref (want all equal, >= 3000)"
# armed: the return type of the first printed prototype is changed
awk 'NR==1{sub(/^static [^ ]+ /,"static ?mutant ")} {print}' "$T/mine.txt" | sort > "$T/mut.txt"
m=$(comm -12 "$T/mut.txt" "$REF" | wc -l)
echo "armed (first prototype mutated): equal=$m total=$total"
[ "$m" -lt "$total" ] || bad "not armed: the mutated prototype still matches"
NAME="T-b equal=$equal/$total reference=$nref"
finish
