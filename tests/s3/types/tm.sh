#!/bin/bash
# T-m (TYPES-1b, the mono instance set). bash tests/s3/types/tm.sh <s3c> (run from the repo root)
#  reference = the generic-def instances in the C that `s2c --no-mem-optimization` emits for Y1: the names of tests/s3/types/ref-protos.txt
#  (regenerated from $S2C when that binary is set, and then it must equal the stored file) that are `f_G__args` for a generic def G of the
#  Y1 sources (`def G [..]`, 96 of them; G with `.` as `__`). `s3c --types-mono Y1` prints `mono f_G__args` for every instance it finds:
#  the closure of the generic call sites over the typed bodies, from the non-generic defs. bar: the two sets are equal, equal == total.
#  by-type-name count = instances; by-layout count (X3e: the type args replaced by their layout class, one C body per key) = layoutkeys.
#  bar: layoutkeys * 5 <= instances (X3e measured 1109 Coll fns -> 91 bodies).
#  armed: one instance dropped from the printed set, and one name changed: equal must fall below total.
. tests/s3/lib.sh
init T-m "$1"
export LC_ALL=C
REF=tests/s3/types/ref-protos.txt
num() { printf '%s\n' "$1" | sed -n "s/.* $2=\([0-9]*\).*/\1/p" | head -1; }
if [ -n "${S2C:-}" ] && [ -x "$S2C" ]; then
  timeout 120 "$S2C" --no-mem-optimization $Y1 2>/dev/null | grep '^static .* f_.*);$' | sort > "$T/fresh.txt"
  cmp -s "$T/fresh.txt" "$REF" || bad "stored reference differs from a fresh s2c run"
fi
# the generic defs of the sources, C-mangled
cat $Y1 | sed -n 's/^def \([A-Za-z0-9_.]*\) *\[.*/\1/p' | sed 's/\./__/g' | sort -u > "$T/gen.txt"
# the reference instance names: f_G__args
sed -n 's/^static .*[ *]\(f_[A-Za-z0-9_]*\)(.*/\1/p' "$REF" | sort -u > "$T/names.txt"
awk 'NR==FNR{g["f_" $0 "__"]=1; next} { for (k in g) if (index($0, k)==1) { print; break } }' "$T/gen.txt" "$T/names.txt" | sort -u > "$T/ref.txt"
timeout 60 "$BIN" --types-mono $Y1 > "$T/out.txt"
grep '^mono ' "$T/out.txt" | sed 's/^mono //' | sort > "$T/mine.txt"
total=$(wc -l < "$T/mine.txt"); nref=$(wc -l < "$T/ref.txt")
equal=$(comm -12 "$T/mine.txt" "$T/ref.txt" | wc -l)
echo "T-m instances by type name: equal=$equal total=$total reference=$nref (generic defs: $(wc -l < "$T/gen.txt"))"
comm -23 "$T/mine.txt" "$T/ref.txt" | head -10 | sed 's/^/  extra   /'
comm -13 "$T/mine.txt" "$T/ref.txt" | head -10 | sed 's/^/  missing /'
[ "$total" -ge 1000 ] && [ "$equal" = "$total" ] && [ "$equal" = "$nref" ] || bad "equal=$equal total=$total reference=$nref (want all equal, >= 1000)"
sum=$(grep '^types:' "$T/out.txt" | head -1)
inst=$(num "$sum" instances); lay=$(num "$sum" layoutkeys)
echo "T-m by layout class: instances=$inst layoutkeys=$lay (bar: layoutkeys * 5 <= instances)"
[ "$inst" = "$total" ] || bad "summary instances=$inst differs from the printed $total"
[ "${lay:-0}" -ge 1 ] && [ "$((${lay:-0} * 5))" -le "${inst:-0}" ] || bad "layoutkeys=$lay of instances=$inst (want layoutkeys * 5 <= instances)"
# armed
sed '1d' "$T/mine.txt" > "$T/drop.txt"
sed '1s/^f_/f_X/' "$T/mine.txt" | sort > "$T/chg.txt"
d=$(comm -12 "$T/drop.txt" "$T/ref.txt" | wc -l); c=$(comm -12 "$T/chg.txt" "$T/ref.txt" | wc -l)
echo "armed: one dropped equal=$d of $nref, one changed equal=$c of $nref"
[ "$d" -lt "$nref" ] && [ "$c" -lt "$nref" ] || bad "not armed: the dropped / changed set still equals the reference"
NAME="T-m bytype=$total/$nref bylayout=$lay"
finish
