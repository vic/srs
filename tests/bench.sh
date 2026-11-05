#!/usr/bin/env bash
# srs speed oracle (vic 2026-11-05): hyperfine times each case, the result must not be slower than bench/baseline.txt.
# the gated cases run the current compiler on a frozen input, bench/corpus (vic 2026-11-06: "frozen corpus for
# comparissions"), so a compiler is compared with a compiler, not a bigger source with a smaller one.
# info-* cases time the current source: they are reported, never a gate.
# slower = mean above the baseline mean by more than 2 combined standard deviations (noise of both runs).
# usage: tests/bench.sh [update]   (update: save this run as the new baseline, after a faster delivery or a refreeze)
# needs $B/s2 (tests/run.sh builds it).
set -u
B=${B:-${XDG_RUNTIME_DIR:-/tmp}/srs-build}
C=bench/corpus
S1SRC=$(sed -n 's/^S1SRC="\(.*\)"$/\1/p' tests/run.sh)
LIBS=$(sed -n 's/^LIBS="\(.*\)"$/\1/p' tests/run.sh)
# the corpus has the S1 file list of its own time: every lib/ and s1/ file it holds, in the order of S1SRC
CS1=""; for f in $S1SRC; do [ -f "$C/$f" ] && CS1="$CS1 $C/$f"; done
CLEAN=${CS1% "$C"/s1/main.srs}
CLIBS=""; for f in $LIBS; do CLIBS="$CLIBS $C/$f"; done
test -x "$B/s2" || { echo "no $B/s2: run tests/run.sh first" >&2; exit 1; }
# every pass test of the corpus checked and emitted in one command
printf '%s\n' "for t in $C/tests/*.srs; do \"$B/s2\" $CLIBS \"\$t\" > /dev/null; done" > "$B/bench-tests.sh"
timeout 300 hyperfine -N -w 3 -m 10 --export-json "$B/bench.json" \
  -n corpus-self "$B/s2 $CS1" \
  -n corpus-lean "$B/s2 --lean Impl $CLEAN" \
  -n corpus-tests "bash $B/bench-tests.sh" \
  -n info-s1-self "$B/s2 $S1SRC" \
  -n info-s1-lean "$B/s2 --lean Impl ${S1SRC% s1/main.srs}" > "$B/bench.log" 2>&1 || { cat "$B/bench.log"; exit 1; }
# per case: name, wall mean + sd (s), instructions mean + sd, peak memory (bytes); hyperfine 2 json
jq -r '.results[] | .summary as $s | "\(.name) wall \($s.time_wall_clock.mean) \($s.time_wall_clock.stddev)\n\(.name) instr \($s.instructions.mean) \($s.instructions.stddev)\n\(.name) mem \($s.memory_peak_resident.mean) \($s.memory_peak_resident.stddev)"' \
  "$B/bench.json" > "$B/bench.now"
if [ "${1:-}" = update ]; then cp "$B/bench.now" bench/baseline.txt; echo "baseline saved:"; cat bench/baseline.txt; exit 0; fi
fail=0
while read -r name metric mean sd; do
  base=$(awk -v n="$name" -v k="$metric" '$1 == n && $2 == k {print $3, $4}' bench/baseline.txt)
  [ -n "$base" ] || { echo "NEW $name $metric $mean (no baseline)"; continue; }
  verdict=$(awk -v m="$mean" -v s="$sd" -v b="${base% *}" -v t="${base#* }" \
    'BEGIN { lim = b + 2 * sqrt(s * s + t * t); printf "%s %.6g (baseline %.6g, limit %.6g, %+.1f%%)", (m > lim ? "SLOWER" : "ok"), m, b, lim, 100 * (m - b) / b }')
  case "$name" in info-*) echo "info ${verdict#* } $name $metric"; continue;; esac
  echo "$verdict $name $metric"
  case "$verdict" in SLOWER*) fail=1;; esac
done < "$B/bench.now"
exit $fail
