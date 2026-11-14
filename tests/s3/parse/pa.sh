#!/bin/bash
# P-a: the per-kind decl counts of `s3c --decls` over Y1 == the grep counts of the decl keywords at the start of a line == the
# PARSE-0 numbers (def 2354 enum 397 extern 96 handler 16 capability 14 trait 2 type 1, 2880 in all).
# bash tests/s3/parse/pa.sh <s3c> (from the repo root). Armed: an expected def count of 2355 must fail.
. tests/s3/lib.sh
init P-a "$1"

pa() { # EXPECTED-DEF-COUNT -> sets PAFAIL
  PAFAIL=0
  out=$(timeout 20 "$BIN" --decls $Y1) || { bad "s3c --decls failed"; PAFAIL=1; return; }
  for kv in def:$1 enum:397 extern:96 handler:16 capability:14 trait:2 type:1; do
    k=${kv%%:*}; e=${kv##*:}
    g=$(echo "$out" | awk -v k=$k '$1==k && NF==2 {print $2}')
    gr=$(cat $Y1 | grep -c "^$k\b")
    echo "$k s3c=$g grep=$gr expect=$e"
    [ "$g" = "$e" ] && [ "$gr" = "$e" ] || PAFAIL=1
  done
  tot=$(echo "$out" | awk 'NF==2 && $1!="total" && $1!~/\.srs$/ {s+=$2} END{print s}')
  echo "total s3c=$tot expect=2880"
  [ "$tot" = 2880 ] || PAFAIL=1
}
pa 2354
[ $PAFAIL = 0 ] || bad "counts differ"
pa 2355 > /dev/null
echo "armed (def expected 2355): fail=$PAFAIL"
[ $PAFAIL = 1 ] || bad "not armed: def=2355 passed"
finish
