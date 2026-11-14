#!/bin/bash
# P-b: per file, the decl ranges [head,bodyHi) of `s3c --decls-dump` are ordered and disjoint, head <= lo <= hi, and every token
# outside them is nl | dedent | doc. Both lex modes. bash tests/s3/parse/pb.sh <s3c> (from the repo root).
# Armed: a first decl range collapsed to empty must be reported.
. tests/s3/lib.sh
init P-b "$1"

pb() { # MODE(skip|keep) TAMPER(0|1) FILES -> prints lines, sets PBTOK PBDECL PBBAD
  m=$1; tamper=$2; shift 2
  dflag=--decls-dump; lflag=--lex-dump; [ $m = keep ] && { dflag=--decls-dump-keep; lflag=--lex-dump-keep; }
  PBTOK=0; PBDECL=0; PBBAD=0
  for f in "$@"; do
    timeout 20 "$BIN" $lflag $f | awk '$1!="diag"' > "$T/lex"
    timeout 20 "$BIN" $dflag $f | awk '$1!="diag"' > "$T/dec"
    r=$(awk -v f=$f -v tamper=$tamper 'NR==FNR { kind[FNR-1]=$1; nt=FNR; next }
      { nd++; h=$3; lo=$4; hi=$5
        if (tamper && FNR==1) hi=h
        if (!(h<hi)) { print f": decl "FNR" head>=hi"; bad++ }
        if (!(h<=lo && lo<=hi)) { print f": decl "FNR" lo out of [head,hi]"; bad++ }
        if (h<prev) { print f": decl "FNR" overlaps or out of order (head "h" < prev hi "prev")"; bad++ }
        for (i=h;i<hi;i++) cov[i]=1; prev=hi }
      END { for (i=0;i<nt;i++) if (!cov[i] && kind[i]!="nl" && kind[i]!="dedent" && kind[i]!="doc") { print f": token "i" ("kind[i]") uncovered"; bad++ }
            if (hi>nt) { print f": last hi "hi" > tokens "nt; bad++ }
            print "#" nt " " nd " " bad+0 }' "$T/lex" "$T/dec")
    echo "$r" | grep -v '^#' | head -3
    read -r a b c <<<"$(echo "$r" | grep '^#' | tr '#' ' ')"
    PBTOK=$((PBTOK+a)); PBDECL=$((PBDECL+b)); PBBAD=$((PBBAD+c))
  done
}

for m in skip keep; do
  pb $m 0 $Y1
  echo "files=$(echo $Y1 | wc -w) tokens=$PBTOK decls=$PBDECL violations=$PBBAD mode=$m"
  [ $PBBAD = 0 ] && [ $PBDECL -gt 0 ] || bad "mode $m: violations=$PBBAD decls=$PBDECL"
done
pb skip 1 lib/prelude.srs > /dev/null
echo "armed (first range emptied): violations=$PBBAD"
[ $PBBAD -gt 0 ] || bad "not armed: a collapsed range passed"
finish
