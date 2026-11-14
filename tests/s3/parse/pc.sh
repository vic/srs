#!/bin/bash
# P-c: 20 decls picked by `shuf --random-source=<(yes)` (the same 20 every run): the name text s3c --decls-dump gives == the
# identifier after the keyword on the source line. bash tests/s3/parse/pc.sh <s3c> (from the repo root).
# Armed: with every s3c name spoiled (an x prefix) all 20 must differ.
. tests/s3/lib.sh
init P-c "$1"

: > "$T/all"
for f in $Y1; do
  grep -nE '^(def|enum|extern|handler|capability|trait|type|val|given)\b' $f | awk -F: -v f=$f '{print f"\t"$1"\t"NR"\t"substr($0, index($0,":")+1)}' >> "$T/all"
done
echo "decls listed: $(wc -l < "$T/all")"
shuf -n 20 --random-source=<(yes) "$T/all" > "$T/pick"

pc() { # SPOIL(0|1) -> sets PCBAD
  PCBAD=0
  while IFS=$'\t' read -r f ln idx txt; do
    exp=$(echo "$txt" | sed -E 's/^extern( "[^"]*")? (def|struct|val) //; s/^(def|enum|extern|handler|capability|trait|type|val|given) //' | grep -oE '^[A-Za-z0-9_.]+')
    act=$(timeout 20 "$BIN" --decls-dump $f | awk '$1!="diag"' | sed -n "${idx}p" | awk '{print $2}')
    [ "$1" = 1 ] && act="x$act"
    if [ "$exp" = "$act" ]; then [ "$1" = 0 ] && echo "ok   $f:$ln exp=$exp act=$act"; else [ "$1" = 0 ] && echo "BAD  $f:$ln exp=$exp act=$act"; PCBAD=$((PCBAD+1)); fi
  done < "$T/pick"
}
pc 0
echo "bad=$PCBAD of $(wc -l < "$T/pick")"
[ $PCBAD = 0 ] && [ "$(wc -l < "$T/pick")" = 20 ] || bad "bad=$PCBAD"
pc 1
echo "armed (names spoiled): bad=$PCBAD of 20"
[ $PCBAD = 20 ] || bad "not armed: spoiled names gave bad=$PCBAD"
finish
