#!/bin/bash
# NEG: every tests/s2/neg file with `// expect: error[parse]` must give a parse FAIL or a skeleton DIAG from `s3c --rt` at the line
# of its `// expect: --> FILE:LINE` (tests/run.sh convention). No expected line: only a FAIL or DIAG must exist.
# bash tests/s3/parse/neg.sh <s3c> (from the repo root). Armed: the expected lines + 1 must fail for the files that have one.
. tests/s3/lib.sh
init P-neg "$1"
DIR=tests/s2/neg

neg() { # OFF -> sets NTOT NOK
  NTOT=0; NOK=0
  for f in $DIR/*.srs; do
    grep -q 'expect: error\[parse\]' "$f" || continue
    NTOT=$((NTOT+1))
    exp=$(grep -h 'expect: -->' "$f" | head -1 | sed 's/.*://')
    out=$(timeout 20 "$BIN" --rt "$f" | grep '^FAIL .* parse-error\|^DIAG ')
    if [ -n "$exp" ]; then
      exp=$((exp+$1))
      if printf '%s\n' "$out" | grep -qF "$f:$exp"; then st=ok; NOK=$((NOK+1)); else st=FAIL; fi
      [ "$1" = 0 ] && echo "$st $f expect-line=$exp got=[$(printf '%s' "$out" | grep -o "$f:[0-9]*" | sort -u | tr '\n' ' ')]"
    else
      if [ -n "$out" ]; then st=ok; NOK=$((NOK+1)); else st=FAIL; fi
      [ "$1" = 0 ] && echo "$st $f no-expected-line got=[$(printf '%s' "$out" | grep -o "$f:[0-9]*" | sort -u | tr '\n' ' ')]"
    fi
  done
}
neg 0
echo "NEG matched $NOK/$NTOT"
[ "$NOK" = "$NTOT" ] && [ "$NTOT" -gt 0 ] || bad "matched $NOK/$NTOT"
neg 1 > /dev/null
echo "armed (lines +1): matched $NOK/$NTOT"
[ "$NOK" -lt "$NTOT" ] || bad "not armed: shifted lines still match"
finish
