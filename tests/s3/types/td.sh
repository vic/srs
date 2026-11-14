#!/bin/bash
# T-d (TYPES-1, negative programs). bash tests/s3/types/td.sh <s3c> (run from the repo root)
#  every tests/s2/neg file expecting error[mismatch]: `s3c --types lib/prelude.srs FILE` prints `mismatch FILE:LINE text` and the
#  expected line (`// expect: --> FILE:LINE`; none: any line) must be among them. OFF=1 shifts the expected lines (the arming).
#  bar: every such file passes. The final line carries the measured ratio; the files that miss are listed.
. tests/s3/lib.sh
init T-d "$1"
run() { # OFF -> sets NP NF, prints the misses
  NP=0; NF=0; MISS=""
  for f in $(grep -l 'expect: error\[mismatch\]' tests/s2/neg/*.srs); do
    exp=$(awk -v off="$1" '/expect: error\[/{u=($0 ~ /mismatch/)} /expect: -->/{ if(u){n=split($0,a,":"); print a[n]+off} }' "$f" | sort -un | tr '\n' ' ')
    got=$(timeout 20 "$BIN" --types lib/prelude.srs "$f" | awk -v f="$f" '$1=="mismatch" && index($2,f":")==1{split($2,a,":"); print a[2]}' | sort -un | tr '\n' ' ')
    ok=1
    if [ -n "$exp" ]; then for e in $exp; do case " $got " in *" $e "*) ;; *) ok=0;; esac; done
    else [ -n "$got" ] || ok=0; fi
    if [ $ok = 1 ]; then NP=$((NP+1)); else NF=$((NF+1)); MISS="$MISS $(basename $f)(exp=[$exp]got=[$got])"; fi
  done
}
run "${OFF:-0}"
total=$((NP+NF))
echo "T-d mismatch negatives: pass=$NP of $total"
for m in $MISS; do echo "  miss $m"; done
[ "$NF" = 0 ] && [ "$total" -ge 20 ] || bad "pass=$NP of $total (want all, >= 20 files)"
run 1 > /dev/null
echo "armed (expected lines +1): pass=$NP of $total"
[ "$NF" -ge 1 ] || bad "not armed: shifted lines still pass"
finish
