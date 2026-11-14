#!/bin/bash
# N-c: every expected unknown-name line of tests/s2/neg is Unresolved in `s3c --names-dump lib/prelude.srs FILE`.
# bash tests/s3/names/nc.sh <s3c> (from the repo root). OFF=n shifts the expected lines; the script arms itself with OFF=1.
. tests/s3/lib.sh
init N-c "$1"

nc() { # OFF -> sets NP NF
  NP=0; NF=0
  for f in $(grep -l 'expect: error\[unknown-name\]' tests/s2/neg/*.srs); do
    exp=$(awk -v off="$1" '/expect: error\[/{u=($0 ~ /unknown-name/)} /expect: -->/{ if(u){n=split($0,a,":"); print a[n]+off} }' $f | sort -un | tr '\n' ' ')
    got=$(timeout 20 "$BIN" --names-dump lib/prelude.srs $f | awk -v f=$f 'index($1,f":")==1 && $3=="Unresolved"{split($1,a,":"); print a[2]}' | sort -un | tr '\n' ' ')
    ok=1; for e in $exp; do case " $got " in *" $e "*) ;; *) ok=0;; esac; done
    if [ $ok = 1 ] && [ -n "$exp" ]; then NP=$((NP+1)); else NF=$((NF+1)); [ "$1" = "${OFF:-0}" ] && echo "FAIL $f exp=[$exp] got=[$got]"; fi
  done
}
nc "${OFF:-0}"
echo "N-c pass=$NP fail=$NF"
[ "$NF" = 0 ] && [ "$NP" -gt 0 ] || bad "pass=$NP fail=$NF"
nc 1 > /dev/null
echo "armed (expected lines +1): pass=$NP fail=$NF"
[ "$NF" -ge 1 ] || bad "not armed: shifted lines still pass"
finish
