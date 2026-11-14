#!/bin/bash
# N-b': every Local ref of `s3c --names-dump` over Y1 lies in ONE decl range with its binder token (the ranges come from
# --decls-dump, per file). bash tests/s3/names/nbp.sh <s3c> (from the repo root).
# Armed: a use token moved past its decl (ut + 1000000) must be counted as a use without range.
. tests/s3/lib.sh
init N-b "$1"

: > "$T/ranges"
for f in $Y1; do
  timeout 20 "$BIN" --decls-dump $f | awk -v f=$f '$1=="def"||$1=="enum"||$1=="extern"||$1=="handler"||$1=="capability"||$1=="trait"||$1=="type"||$1=="val"||$1=="given"{print f, $3, $5}' >> "$T/ranges"
done
timeout 40 "$BIN" --names-dump $Y1 > "$T/dump"

nbp() { # TAMPER(0|1) -> sets NBTOT NBCROSS NBNORANGE
  eval "$(awk -v R="$T/ranges" -v tamper="$1" '
  BEGIN{ while((getline l < R)>0){ split(l,a," "); n[a[1]]++; lo[a[1], n[a[1]]]=a[2]+0; hi[a[1], n[a[1]]]=a[3]+0 } }
  $3=="Local"{
    p=$1; sub(/:[0-9]+$/,"",p)
    split($5,u,"="); split($6,t,"="); ut=u[2]+0; tt=t[2]+0
    if (tamper) ut+=1000000
    total++
    ur=0; tr=0
    for(i=1;i<=n[p];i++){ if(lo[p,i]<=ut && ut<hi[p,i]) ur=i; if(lo[p,i]<=tt && tt<hi[p,i]) tr=i }
    if(ur==0) noRange++
    else if(ur!=tr) cross++
  }
  END{ print "NBTOT=" total+0 " NBCROSS=" cross+0 " NBNORANGE=" noRange+0 }' "$T/dump")"
}
nbp 0
echo "N-b: Local refs=$NBTOT cross-decl=$NBCROSS use-without-range=$NBNORANGE"
[ "$NBTOT" -gt 0 ] && [ "$NBCROSS" = 0 ] && [ "$NBNORANGE" = 0 ] || bad "refs=$NBTOT cross=$NBCROSS norange=$NBNORANGE"
nbp 1
echo "armed (use tokens moved): use-without-range=$NBNORANGE of $NBTOT"
[ "$NBNORANGE" = "$NBTOT" ] || bad "not armed: moved tokens not all counted"
finish
