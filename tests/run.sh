#!/usr/bin/env bash
# build S0 and run tests/*.srs through it. each test: exit 0 + stdout == tests/<name>.out
set -u
B=${B:-${XDG_RUNTIME_DIR:-/tmp}/srs-build}; mkdir -p "$B"
timeout 120 zig build-exe s0/main.zig -femit-bin="$B/s0" || exit 1
fail=0
for t in tests/*.srs; do
  n=$(basename "$t" .srs)
  "$B/s0" lib/prelude.srs "$t" > "$B/$n.c" || { echo "FAIL $n (s0)"; fail=1; continue; }
  timeout 60 zig cc -std=gnu11 -O1 -w -o "$B/$n" "$B/$n.c" rt/srs_rt.c || { echo "FAIL $n (cc)"; fail=1; continue; }
  out=$(timeout 1 "$B/$n"); code=$?
  if [ $code -ne 0 ] || [ "$out" != "$(cat tests/$n.out)" ]; then echo "FAIL $n exit=$code"; fail=1; else echo "ok $n"; fi
done
exit $fail
