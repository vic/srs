#!/bin/bash
# N-base: the `--names` baselines over Y1 (31 files): unresolved=0 locals=19852 resolved=62405 leaks=0 parseErr=0 overflow=0 dups=0,
# and no unresolved type (tunresolved=0). bash tests/s3/names/nbase.sh <s3c> (from the repo root).
# Armed: the same check with locals=19853 must fail. The numbers change only with names.srs or the Y1 sources (then re-measure).
. tests/s3/lib.sh
init N-base "$1"

out=$(timeout 40 "$BIN" --names $Y1)
echo "$out" | head -4
chk() { # LOCALS
  echo "$out" | head -1 | grep -q "^globals=[0-9]* locals=$1 resolved=62405 unresolved=0 types=[0-9]* tresolved=[0-9]* tunresolved=0\$" &&
  echo "$out" | grep -q ' dups=0 maxScope=[0-9]* parseErr=0 overflow=0 leaks=0$'
}
chk 19852 || bad "baseline differs (locals=19852 resolved=62405 unresolved=0 tunresolved=0 leaks=0 parseErr=0 overflow=0)"
if chk 19853; then bad "not armed: locals=19853 matched"; else echo "armed (locals=19853): no match"; fi
finish
