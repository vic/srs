#!/usr/bin/env bash
# souffle-oracle.sh <file.dl> [run-name]   (run from the repo root; reference workbench, not part of run.sh: Souffle is slow to build)
# Runs compiled Souffle 2.5 -j1 on the Y1 Mem facts, compares every VERDICT relation (the relations Mem.report reads via
# D.tuples, listed in tests/s3/dl/verdict.rels) against the baseline output (sorted cmp), prints EQUAL/DIFF per relation,
# total rows and perf instr:u. exit 0 = all verdict relations EQUAL, 1 = any DIFF, 2 = build/run failure.
# DATA: $S3_DL_DATA (default $HOME/.cache/srs3/dl) holds facts/ and baseline/. Souffle compile ~65 s wall, run ~1 s.
# usage example: bash tests/s3/dl/souffle-oracle.sh tests/s3/dl/mem2.dl ctl
set -u
if [ -z "${ORACLE_IN_NIX:-}" ]; then
  exec nix-shell -I nixpkgs=https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz -p souffle perf \
    --run "ORACLE_IN_NIX=1 bash $0 $*"
fi
dl=${1:?usage: souffle-oracle.sh file.dl [run-name]}
name=${2:-$(basename "$dl" .dl)}
DATA=${S3_DL_DATA:-$HOME/.cache/srs3/dl}
R=$(mktemp -d "${TMPDIR:-/tmp}/souffle-$name.XXXXXX") || exit 2
trap 'rm -rf "$R"' EXIT
mkdir -p "$R/out"
cp "$dl" "$R/in.dl" || exit 2
t0=$(date +%s)
timeout 300 souffle -o "$R/prog" -j1 "$R/in.dl" > "$R/build.log" 2>&1 || { echo "BUILD FAIL"; tail -5 "$R/build.log"; exit 2; }
echo "build_wall_s=$(( $(date +%s) - t0 ))"
timeout 120 perf stat -e instructions:u -x, -o "$R/perf.stat" "$R/prog" -F "$DATA/facts" -D "$R/out" || { echo "RUN FAIL"; exit 2; }
bad=0
while read -r rel; do
  if [ ! -f "$R/out/$rel.csv" ]; then echo "DIFF   $rel (no output file)"; bad=1; continue; fi
  if cmp -s <(sort "$DATA/baseline/$rel.csv") <(sort "$R/out/$rel.csv"); then
    echo "EQUAL  $rel $(wc -l < "$R/out/$rel.csv")"
  else
    echo "DIFF   $rel base=$(wc -l < "$DATA/baseline/$rel.csv") now=$(wc -l < "$R/out/$rel.csv")"; bad=1
  fi
done < tests/s3/dl/verdict.rels
echo "total_rows=$(cat "$R"/out/*.csv | wc -l) (baseline $(cat "$DATA"/baseline/*.csv | wc -l))"
echo "instr_u=$(grep instructions "$R/perf.stat" | cut -d, -f1)"
[ "$bad" = 0 ] && echo "PASS souffle-oracle" || echo "FAIL souffle-oracle"
exit "$bad"
