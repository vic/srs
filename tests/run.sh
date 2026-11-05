#!/usr/bin/env bash
# srs gate, self-hosted (C10): bootstrap/seed.c (srs, C) builds S1; S1 compiles its own src (fixpoint);
# tests/*.srs: S1 compile + run, stdout == .out; tests/neg/*.srs: S1 rejects with "// expect:" text.
# S0 (zig) only when the seed cannot build the src: s0-bootstrap.
set -u
B=${B:-${XDG_RUNTIME_DIR:-/tmp}/srs-build}; mkdir -p "$B"
CC="zig cc -std=gnu11 -O1 -w"
S1SRC="lib/prelude.srs s1/node.srs s1/lex.srs s1/parse.srs s1/check.srs s1/given.srs s1/mono.srs s1/emit.srs s1/lean.srs s1/leanspec.srs s1/main.srs"
LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/list.lib tests/file.lib"
fail=0
timeout 120 $CC -o "$B/seed" bootstrap/seed.c rt/srs_rt.c || exit 1
timeout 10 "$B/seed" $S1SRC > "$B/s1.c" && timeout 120 $CC -o "$B/s1" "$B/s1.c" rt/srs_rt.c || exit 1
timeout 10 "$B/s1" $S1SRC > "$B/s2.c" && timeout 120 $CC -o "$B/s2" "$B/s2.c" rt/srs_rt.c || exit 1
timeout 10 "$B/s2" $S1SRC > "$B/s3.c" || exit 1
if cmp -s "$B/s2.c" "$B/s3.c"; then echo "ok fixpoint s2.c == s3.c"; else echo "FAIL fixpoint"; fail=1; fi
if cmp -s bootstrap/seed.c "$B/s2.c"; then echo "ok seed == s2.c"; else echo "FAIL seed stale: seed-update"; fail=1; fi
for t in tests/*.srs; do
  n=$(basename "$t" .srs)
  timeout 2 "$B/s2" $LIBS "$t" > "$B/$n.c" || { echo "FAIL $n (s1)"; fail=1; continue; }
  timeout 60 $CC -o "$B/$n" "$B/$n.c" rt/srs_rt.c || { echo "FAIL $n (cc)"; fail=1; continue; }
  out=$(timeout 1 "$B/$n"); code=$?
  if [ $code -ne 0 ] || [ "$out" != "$(cat tests/$n.out)" ]; then echo "FAIL $n exit=$code out=$out"; fail=1; else echo "ok $n"; fi
done
for t in tests/neg/*.srs; do
  n=$(basename "$t" .srs); want=$(sed -n "1s|^// expect: ||p" "$t")
  msg=$(timeout 2 "$B/s2" $LIBS "$t" 2>&1 >/dev/null); code=$?
  case "$msg" in *"$want"*) [ $code -eq 1 ] && { echo "ok neg/$n"; continue; };; esac
  echo "FAIL neg/$n exit=$code msg=$msg"; fail=1
done
exit $fail
