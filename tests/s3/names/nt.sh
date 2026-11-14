#!/bin/bash
# N-t (NAMES-1b, the type namespace). bash tests/s3/names/nt.sh <s3c> (run from the repo root)
#  1. Y1: `--names` reports types=T tresolved=R tunresolved=0 with T > 0 and a TypeUnresolved count of 0
#  2. neg: every tests/s2/neg file expecting error[unknown-type] has a TypeUnresolved use at its expected line
#     (no expected line: at least one TypeUnresolved in the file). OFF=1 shifts the expected lines (the arming)
#  3. standing: tests/s3/names/nty.srs, the type namespace beside the value namespace (dump line: path:line text kind target)
. tests/s3/lib.sh
init N-t "$1"

# 1. Y1
out=$(timeout 40 "$BIN" --names $Y1)
line=$(printf '%s\n' "$out" | head -1)
echo "Y1: $line"
ty=$(printf '%s\n' "$line" | sed -n 's/.* types=\([0-9]*\) tresolved=\([0-9]*\) tunresolved=\([0-9]*\).*/\1 \2 \3/p')
set -- $ty
[ -n "$ty" ] && [ "$1" -gt 0 ] && [ "$3" = 0 ] && [ "$1" = "$2" ] || bad "Y1 types/tresolved/tunresolved = [$ty]"
printf '%s\n' "$out" | grep -q '^type ' && bad "Y1 lists unresolved types"

# 2. neg
negrun() { # OFF -> prints per-file lines, sets NP NF
  NP=0; NF=0
  for f in $(grep -l 'expect: error\[unknown-type\]' tests/s2/neg/*.srs); do
    exp=$(awk -v off="$1" '/expect: error\[/{u=($0 ~ /unknown-type/)} /expect: -->/{ if(u){n=split($0,a,":"); print a[n]+off} }' "$f" | sort -un | tr '\n' ' ')
    got=$(timeout 20 "$BIN" --names-dump lib/prelude.srs "$f" | awk -v f="$f" 'index($1,f":")==1 && $3=="TypeUnresolved"{split($1,a,":"); print a[2]}' | sort -un | tr '\n' ' ')
    ok=1
    if [ -n "$exp" ]; then for e in $exp; do case " $got " in *" $e "*) ;; *) ok=0;; esac; done
    else [ -n "$got" ] || ok=0; fi
    if [ $ok = 1 ]; then NP=$((NP+1)); else NF=$((NF+1)); echo "  miss $f exp=[$exp] got=[$got]"; fi
  done
}
negrun "${OFF:-0}"
echo "neg unknown-type: pass=$NP fail=$NF"
[ "$NF" = 0 ] && [ "$NP" -ge 3 ] || bad "neg unknown-type pass=$NP fail=$NF (want fail=0, pass>=3)"
negrun 1 > "$T/arm.txt"
echo "armed (expected lines +1): pass=$NP fail=$NF"
[ "$NF" -ge 1 ] || bad "not armed: shifted lines still pass"

# 3. standing
D=$(timeout 20 "$BIN" --names-dump lib/prelude.srs tests/s3/names/nty.srs)
has() { # line text kind target-prefix
  c=$(printf '%s\n' "$D" | awk -v p="tests/s3/names/nty.srs:$1" -v t="$2" -v k="$3" -v tg="$4" '$1==p && $2==t && $3==k && index($4,tg)==1' | wc -l)
  if [ "$c" -ge 1 ]; then echo "ok   $1 $2 $3 $4"; else echo "FAIL $1 $2 $3 $4 (got none)"; bad "standing $1 $2 $3"; fi
}
has 2 A TypeTyParam 1:A
has 8 A TypeTyParam 7:A
has 6 Opt TypeEnum 1:1:Opt
has 12 Mk TypeEnum 1:4:Mk
has 13 Cx TypeCap 1:9:Cx
has 15 Nope TypeUnresolved -
has 16 A TypeTyParam 16:A
has 16 A Local 16:A
has 18 Hx TypeHandler 1:13:Hx
has 19 Mk TypeEnum 1:4:Mk
has 19 Mk Case 1:5:Mk
has 5 I64 TypeBuiltin -
# the arming of the standing check: a wrong expectation must be missed
c=$(printf '%s\n' "$D" | awk '$1=="tests/s3/names/nty.srs:15" && $2=="Nope" && $3=="TypeEnum"' | wc -l)
echo "armed (Nope as TypeEnum): matches=$c"
[ "$c" = 0 ] || bad "not armed: wrong kind matched"
finish
