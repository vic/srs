#!/bin/bash
# O-a / O-b / O-c over the 31 Y1 files, skip and keep mode. bash tests/s3/lex/oab.sh <s3c> (from the repo root)
#  O-a: tokens in order, no overlap, in range, token bytes + gap bytes = file size; O-b: every gap byte is whitespace or in a // comment
#  (keep mode: no comment byte in a gap); O-c: no diag, no overflow diag. Armed: a dump with one offset moved must fail O-a,
#  and tests/s3/lex/bad.srs (bad chars, a bad hex) must give diags.
. tests/s3/lib.sh
init O-ab "$1"
AWK=tests/s3/lex/oab.awk

# one file in one mode: prints the awk result line, returns 1 on a violation
oab() { # FILE MODE(skip|keep) [TAMPER]
  f=$1; m=$2; tamper=$3
  if [ "$m" = keep ]; then flag=--lex-dump-keep; kv=1; else flag=--lex-dump; kv=0; fi
  timeout 20 "$BIN" $flag "$f" > "$T/dump" || { echo "FAIL dump of $f"; return 1; }
  timeout 60 od -An -v -tu1 -w1 "$f" > "$T/od"
  sz=$(wc -c < "$f"); odn=$(wc -l < "$T/od")
  [ "$sz" = "$odn" ] || echo "FAIL od lines $odn != wc -c $sz"
  nd=$(grep -c '^diag ' "$T/dump"); nov=$(grep -c '^diag overflow ' "$T/dump")
  if [ -n "$tamper" ]; then awk '$1!="diag" && !d {$2=$2+1; d=1} {print}' "$T/dump" > "$T/dump2"; mv "$T/dump2" "$T/dump"; fi
  timeout 60 awk -v keep=$kv -f "$AWK" "$T/dump" "$T/od" > "$T/res"; r=$?
  sed "s|^|$f $m |" "$T/res"
  [ "$nd" = 0 ] || { echo "$f $m O-c diags=$nd"; r=1; }
  [ "$nov" = 0 ] || { echo "$f $m O-c overflow=$nov"; r=1; }
  return $r
}

nok=0; nbad=0
for f in $Y1; do
  for m in skip keep; do
    if oab "$f" $m > "$T/line"; then nok=$((nok+1)); else nbad=$((nbad+1)); cat "$T/line"; fi
  done
done
echo "O-a/O-b/O-c: $nok ok, $nbad bad (31 files x 2 modes)"
[ "$nbad" = 0 ] && [ "$nok" = 62 ] || bad "ok=$nok bad=$nbad (want 62/0)"

oab lib/prelude.srs skip tamper > "$T/line"; r=$?
echo "armed (offset moved): $(head -1 "$T/line") exit=$r"
[ $r != 0 ] || bad "not armed: a moved offset passed O-a/O-b"
oab tests/s3/lex/bad.srs skip > "$T/line"; r=$?
echo "armed (bad.srs): exit=$r $(grep -c 'O-c diags' "$T/line") O-c row(s)"
[ $r != 0 ] && grep -q 'O-c diags=[1-9]' "$T/line" || bad "not armed: bad.srs gave no O-c diags"
finish
