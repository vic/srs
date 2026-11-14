#!/bin/bash
# P-rt: `s3c --rt` (parse every decl and print it back, compare) over Y1 ends `ALL 2880/2880 parseErr=0 ... overflow=0`.
# bash tests/s3/parse/rt.sh <s3c> (from the repo root). Armed: the same check against 2881 must fail.
. tests/s3/lib.sh
init P-rt "$1"

last=$(timeout 60 "$BIN" --rt $Y1 | tail -1)
echo "$last"
rt() { printf '%s\n' "$last" | grep -q " ALL $1/$1 parseErr=0 nodes=[0-9]* overflow=0\$"; }
rt 2880 || bad "not ALL 2880/2880 with parseErr=0 overflow=0"
if rt 2881; then bad "not armed: 2881 matched"; else echo "armed (2881): no match"; fi
finish
