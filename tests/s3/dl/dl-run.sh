#!/usr/bin/env bash
# dl-run.sh <dl-engine-binary>  (run from the repo root)
# Oracle for the s3 Datalog engine (s3/dl.srs + s3/dlmain.srs built as a binary): plan the Y1 Mem dump with the awk planner,
# run the engine, map ids back to text, compare every relation (sorted) against the Souffle baseline output.
# shortcut: planner + symbol interning in awk (tests/s3/dl/mkplan.awk) until DL-1b moves them into srs.
# DATA: facts + baseline come from $S3_DL_DATA (default $HOME/.cache/srs3/dl); see tests/s3/dl/README.txt to regenerate.
# Prints per-relation DIFF lines, EQUAL=N DIFF=M, then one final line PASS dl-engine / FAIL dl-engine (why).
bin=${1:?usage: dl-run.sh <dl-engine-binary>}
DATA=${S3_DL_DATA:-$HOME/.cache/srs3/dl}
T=$(mktemp -d "${TMPDIR:-/tmp}/dlrun.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
[ -d "$DATA/facts" ] && [ -d "$DATA/baseline" ] || { echo "FAIL dl-engine (no data in $DATA: see tests/s3/dl/README.txt)"; exit 1; }
mkdir -p "$T/p" "$T/out"
timeout 120 gawk -v DL=tests/s3/dl/mem2.dl -v FACTS="$DATA/facts" -v OUT="$T/p" -f tests/s3/dl/mkplan.awk || { echo "FAIL dl-engine (planner)"; exit 1; }
timeout 120 "$bin" "$T/p/in.txt" > "$T/out.txt" || { echo "FAIL dl-engine (engine exit)"; exit 1; }
timeout 120 gawk -v P="$T/p" -v OUT="$T/out" -f tests/s3/dl/unmap.awk "$T/out.txt" || { echo "FAIL dl-engine (unmap)"; exit 1; }
eq=0; bad=0
for f in "$DATA"/baseline/*.csv; do
  r=$(basename "$f" .csv)
  if [ -f "$T/out/$r.csv" ] && cmp -s <(sort "$f") <(sort "$T/out/$r.csv"); then eq=$((eq+1)); else bad=$((bad+1)); echo "DIFF $r"; fi
done
echo "EQUAL=$eq DIFF=$bad total_rows=$(cat "$T"/out/*.csv | wc -l) baseline_rows=$(cat "$DATA"/baseline/*.csv | wc -l)"
if [ "$bad" = 0 ] && [ "$eq" = 65 ]; then echo "PASS dl-engine"; exit 0; else echo "FAIL dl-engine ($bad relations differ, $eq equal of 65)"; exit 1; fi
