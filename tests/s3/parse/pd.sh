#!/bin/bash
# P-d: (1) diags=0 on every Y1 file and no overflow diag; (2) tests/s3/parse/pd.srs (a stray `foo bar` at byte 24 and a bare `def`
# at byte 39): unknownDecl at the token of foo, missingName at the token after the bare def, and no other diag.
# bash tests/s3/parse/pd.sh <s3c> (from the repo root). Armed: the same expectations one token off must not match.
. tests/s3/lib.sh
init P-d "$1"

out=$(timeout 20 "$BIN" --decls $Y1)
echo "files with diags=0: $(echo "$out" | grep -c ' decls=.* diags=0$') of $(echo $Y1 | wc -w)"
echo "$out" | grep 'total diags'
nz=$(echo "$out" | grep -c ' diags=[1-9]'); [ "$nz" = 0 ] || bad "$nz Y1 files with diags"
ov=0; for f in $Y1; do c=$(timeout 20 "$BIN" --decls-dump $f | grep -c '^diag overflow'); ov=$((ov+c)); done
echo "overflow diags over Y1: $ov"; [ $ov = 0 ] || bad "overflow diags $ov"

P=tests/s3/parse/pd.srs
timeout 20 "$BIN" --lex-dump $P | awk '$1!="diag"{print NR-1, $0}' > "$T/lex"
timeout 20 "$BIN" --decls-dump $P > "$T/dump"
echo "--- scratch decls"; cat "$T/dump"
foo=$(awk '$2=="ident" && $3==24 {print $1}' "$T/lex")
bare=$(awk '$2=="ident" && $3==39 {print $1}' "$T/lex")
echo "expect unknownDecl at token $foo, missingName at token $((bare+1))"
grep -q "^diag unknownDecl $foo\$" "$T/dump" && echo "ok unknownDecl" || bad "no unknownDecl at $foo"
grep -q "^diag missingName $((bare+1))\$" "$T/dump" && echo "ok missingName" || bad "no missingName at $((bare+1))"
[ "$(grep -c '^diag' "$T/dump")" = 2 ] || bad "diag count != 2"
if grep -q "^diag unknownDecl $((foo+1))\$" "$T/dump" || grep -q "^diag missingName $((bare+2))\$" "$T/dump"; then bad "not armed: one-off token matched"; else echo "armed (token +1): no match"; fi
finish
