#!/bin/bash
# bench (S1b-1): bash tests/s3/corpus/bench.sh <s3c-binary> [--record] (from the repo root; the binary is the SELF-BUILT s3c, bin2z).
# The yardstick is s3c's own source, frozen in tests/s3/corpus/s3c (13 files, order in ORDER, bytes and sha256 in MANIFEST).
# For --types and --emit it measures instructions (callgrind), peak RSS and minor page faults, and compares each with tests/s3/corpus/baseline.txt
# (BASELINE=file overrides): instructions must not be above the baseline, peak RSS and faults not more than 2% above. --record writes the baseline.
# The last line is `PASS bench (...)` or `FAIL bench (why)`. `bash tests/s3/corpus/bench.sh BIN --selftest` lowers the baseline by 10% in a copy and
# requires the comparison to FAIL (the armed control). Needs valgrind (PATH or nix-shell -p valgrind) and /run/current-system/sw/bin/time.
D=tests/s3/corpus
BIN=${1:-}; MODE=${2:-}
[ -x "$BIN" ] || { echo "FAIL bench (no s3c binary: '$BIN')"; exit 1; }
[ -d $D/s3c ] || { echo "FAIL bench (run from the repo root)"; exit 1; }
BASE=${BASELINE:-$D/baseline.txt}
# the corpus is frozen: every file must equal its MANIFEST sha256
bad=0
while IFS="$(printf '\t')" read -r path bytes sha name; do
  [ "$(sha256sum "$D/s3c/$name" | cut -c1-64)" = "$sha" ] || { echo "corpus file changed: $name"; bad=1; }
done < $D/MANIFEST
[ $bad = 0 ] || { echo "FAIL bench (corpus changed: refreeze it on purpose)"; exit 1; }
FILES=""; for n in $(cat $D/s3c/ORDER); do FILES="$FILES $D/s3c/$n"; done
T=$(mktemp -d "${TMPDIR:-/tmp}/bench.XXXXXX"); trap 'rm -rf "$T"' EXIT
VG=valgrind; command -v valgrind > /dev/null || VG="nix-shell -p valgrind --run"
measure() { # mode -> sets IR PEAK FAULTS
  mode=$1
  if [ "$VG" = valgrind ]; then timeout 300 valgrind --tool=callgrind --callgrind-out-file=$T/cg.out "$BIN" $mode $FILES > /dev/null 2> $T/cg.err
  else timeout 300 nix-shell -p valgrind --run "valgrind --tool=callgrind --callgrind-out-file=$T/cg.out $BIN $mode $FILES > /dev/null 2> $T/cg.err"; fi
  IR=$(grep refs $T/cg.err | grep -o '[0-9,]*$' | tr -d ',')
  /run/current-system/sw/bin/time -v "$BIN" $mode $FILES 2> $T/t.err > /dev/null
  PEAK=$(grep 'Maximum resident' $T/t.err | grep -o '[0-9]*$'); FAULTS=$(grep 'Minor' $T/t.err | grep -o '[0-9]*$')
}
if [ "$MODE" = --record ]; then
  { echo "pinned_commit $(cat $D/PINNED)"; echo "lines $(cat $FILES | wc -l)"; echo "bytes $(cat $FILES | wc -c)"
    for m in types emit; do measure --$m; echo "${m}_ir $IR"; echo "${m}_peak_kb $PEAK"; echo "${m}_minflt $FAULTS"; done; } > "$BASE"
  echo "recorded $BASE"; cat "$BASE"; echo "PASS bench (recorded)"; exit 0
fi
if [ "$MODE" = --selftest ]; then
  awk '$1 ~ /_(ir|peak_kb|minflt)$/ { $2 = int($2 * 9 / 10) } { print }' "$BASE" > $T/low.txt
  if BASELINE=$T/low.txt bash $0 "$BIN" > $T/low.out 2>&1; then echo "FAIL bench (selftest: a baseline 10% lower still passed)"; exit 1
  else echo "PASS bench (selftest: a baseline 10% lower fails: $(tail -1 $T/low.out | cut -c1-80))"; exit 0; fi
fi
why=""
for m in types emit; do
  measure --$m
  bi=$(awk -v k=${m}_ir '$1 == k { print $2 }' "$BASE"); bp=$(awk -v k=${m}_peak_kb '$1 == k { print $2 }' "$BASE"); bf=$(awk -v k=${m}_minflt '$1 == k { print $2 }' "$BASE")
  echo "$m: Ir $IR (baseline $bi), peak $PEAK KB (baseline $bp), faults $FAULTS (baseline $bf)"
  # callgrind varies by tens of instructions between runs of one binary (measured 51 on 133.65 M): tolerance 0.01%
  [ "$IR" -le $((bi + bi / 10000)) ] || why="$why $m instructions $IR > $bi +0.01%;"
  [ "$PEAK" -le $((bp * 102 / 100)) ] || why="$why $m peak $PEAK KB > $bp +2%;"
  [ "$FAULTS" -le $((bf * 102 / 100)) ] || why="$why $m faults $FAULTS > $bf +2%;"
done
if [ -z "$why" ]; then echo "PASS bench (instructions, peak and faults not above the baseline)"; exit 0; fi
echo "FAIL bench ($why)"; exit 1
