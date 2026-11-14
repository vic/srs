#!/bin/bash
# O-e: the s3c token sequence of every snippet and file of tests/s2/lex.srs == the same line of tests/s2/lex.out.
# usage: bash tests/s3/lex/oe.sh <s3c> (from the repo root). Armed: a tampered expected line (" xx" appended) must be reported.
. tests/s3/lib.sh
init O-e "$1"

seqawk='
BEGIN { RS="^$"; getline src < F; RS="\n"; nt=0; ni=0; nd=0; fd="" }
{ if ($1=="diag") { if (fd=="") { w=$2; off=$3+0; pre=substr(src,1,off); nl=gsub(/\n/,"",pre);
      m["tab"]="tab"; m["baddedent"]="bad dedent"; m["unterminated"]="unterminated"; m["badchar"]="bad char"; m["bighex"]="big hex"; m["overflow"]="OVERFLOW";
      fd="bad " m[w] " @" (nl+1) } ; ndg++; if ($2=="overflow") nov++; next }
  t=substr(src,$2+1,$3); k=$1
  if (k=="ident") s="id:" t
  else if (k=="int") { if (t ~ /^0[xX]/) { if (t in big) s="int:" big[t]; else s="int:" sprintf("%d", strtonum(t)) } else s="int:" t }
  else if (k=="str") s="str:" substr(t,2,length(t)-2)
  else if (k=="char") s="chr:" substr(t,2,length(t)-2)
  else if (k=="op") s="op:" t
  else if (k=="ltglued") s="ltg"
  else if (k=="nl") s="nl"
  else if (k=="indent") { s="in"; ni++ }
  else if (k=="dedent") { s="de"; nd++ }
  else if (k=="doc") s="doc:" t
  else s="BADKIND"
  out = out (out==""?"":" ") s }
END { if (MODE=="file") print (ndg==0 && ni==nd) ? FN " ok" : FN " bad"
      else if (fd!="") print fd
      else print out }'

# snippets in main order; lines 1-9 of lex.out are the dump calls, 10-13 the LT.file calls
grep -E '^  LT\.dump(Keep)?\("' tests/s2/lex.srs > "$T/calls.txt"
nsn=$(wc -l < "$T/calls.txt")
grep -E '^  LT\.file\("' tests/s2/lex.srs | sed 's/^  LT\.file("\(.*\)")$/\1/' > "$T/files.txt"
nfl=$(wc -l < "$T/files.txt")
[ "$nsn" = 9 ] && [ "$nfl" = 4 ] || { bad "found $nsn snippets $nfl files (expect 9 and 4)"; finish; }

# oe TAMPER: compares the 13 lines; TAMPER = the line number whose expected text is spoiled ("" = none). Sets NBAD.
oe() {
  tamper=$1; NBAD=0; first=0
  for k in $(seq 1 9); do
    call=$(sed -n "${k}p" "$T/calls.txt")
    mode=skip; case "$call" in *dumpKeep*) mode=keep;; esac
    # the literal as printf %b text: drop the call wrapper, unescape \" , then %b makes \n and \t
    lit=$(printf '%s' "$call" | sed 's/^  LT\.dump\(Keep\)\?("//; s/")$//; s/\\"/"/g')
    printf '%b' "$lit" > "$T/s$k.srs"
    if [ $mode = keep ]; then flag=--lex-dump-keep; else flag=--lex-dump; fi
    timeout 20 "$BIN" $flag "$T/s$k.srs" > "$T/d$k.txt" || { bad "s3c crashed on snippet $k"; return; }
    got=$(LC_ALL=C awk -v F="$T/s$k.srs" -v MODE=seq 'BEGIN{big["0x7fffffffffffffff"]="9223372036854775807"} '"$seqawk" "$T/d$k.txt")
    exp=$(sed -n "${k}p" tests/s2/lex.out)
    case "$exp" in bad*) ;; *) exp=$(printf '%s' "$exp" | sed 's/@[0-9]*\( \|$\)/\1/g; s/ $//; s/ eof$//');; esac
    [ "$tamper" = "$k" ] && exp="$exp xx"
    if [ "$got" != "$exp" ]; then NBAD=$((NBAD+1)); if [ $first = 0 ]; then first=$k
      echo "  line $k ($mode): $lit"; echo "    expected: $exp"; echo "    got:      $got"; fi; fi
  done
  for k in 1 2 3 4; do
    f=$(sed -n "${k}p" "$T/files.txt")
    timeout 20 "$BIN" --lex-dump "$f" > "$T/f$k.txt" || { bad "s3c crashed on $f"; return; }
    got=$(LC_ALL=C awk -v F="$f" -v FN="$f" -v MODE=file "$seqawk" "$T/f$k.txt")
    exp=$(sed -n "$((9+k))p" tests/s2/lex.out)
    [ "$tamper" = "$((9+k))" ] && exp="$exp xx"
    if [ "$got" != "$exp" ]; then NBAD=$((NBAD+1)); if [ $first = 0 ]; then first=$((9+k))
      echo "  line $((9+k)): $f"; echo "    expected: $exp"; echo "    got:      $got"; fi; fi
  done
}

oe ""
echo "O-e: $NBAD of 13 lines of tests/s2/lex.out differ"
[ "$NBAD" = 0 ] || bad "$NBAD of 13 lines differ"
for k in 3 11; do
  oe $k > /dev/null
  echo "armed (tamper line $k): differ=$NBAD"
  [ "$NBAD" = 1 ] || bad "not armed: tamper line $k gave $NBAD differing lines"
done
finish
