#!/bin/bash
# Runs every s3 oracle: bash tests/s3/run.sh <s3c-binary>   (run from the repo root; the binary is built from s3/*.srs, see s3/main.srs)
# Each script runs in its own call under `timeout 120` and ends with one line `PASS name` or `FAIL name (why)`; run.sh prints that
# line, then `TOTAL pass=P fail=F`, and exits 1 if any script failed. Full output of a script: run it by itself.
BIN=${1:-}
[ -n "$BIN" ] && [ -x "$BIN" ] || { echo "usage: bash tests/s3/run.sh <s3c-binary> (from the repo root)"; exit 2; }
[ -f s2/names.srs ] || { echo "run from the repo root"; exit 2; }
pass=0; fail=0
run() { # script [args]
  out=$(timeout 120 bash "$@" 2>&1); code=$?
  last=$(printf '%s\n' "$out" | tail -1)
  case "$last" in
    "PASS "*) if [ $code = 0 ]; then pass=$((pass+1)); echo "$last"; else fail=$((fail+1)); echo "FAIL $1 (PASS line with exit $code)"; fi;;
    "FAIL "*) fail=$((fail+1)); echo "$last";;
    *) fail=$((fail+1)); echo "FAIL $1 (exit $code, no result line$([ $code = 124 ] && echo ', timeout 120'): $last)";;
  esac
}
for s in lex/oe lex/oab parse/pa parse/pb parse/pc parse/pd parse/neg parse/rt names/nbase names/nc names/nbp names/standing names/nt; do
  run tests/s3/$s.sh "$BIN"
done
run tests/s3/gate/subset.sh
run tests/s3/gate/armall.sh
echo "TOTAL pass=$pass fail=$fail"
[ $fail = 0 ]
