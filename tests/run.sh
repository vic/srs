#!/usr/bin/env bash
# srs gate, self-hosted (C10): bootstrap/seed.c (srs, C) builds S1; S1 compiles its own src (fixpoint);
# tests/*.srs: S1 compile + run, stdout == .out; tests/neg/*.srs: S1 rejects with "// expect:" text.
# S0 (zig) only when the seed cannot build the src: s0-bootstrap.
set -u
B=${B:-${XDG_RUNTIME_DIR:-/tmp}/srs-build}; mkdir -p "$B"
# tests never touch the user store (vic 2026-11-06): the store of this run lives under $B
export SRS_STORE="$B/store-gate"
CC="zig cc -std=gnu11 -O1 -w"
# the compiler links static on Linux (musl): no dynamic loader per compile (vic-5r9: -13% instr on a small program)
case "$(uname -s)" in Linux) CCS="$CC -static -target $(uname -m)-linux-musl";; *) CCS="$CC";; esac
S1SRC="lib/prelude.srs lib/kanren.srs lib/datalog.srs s1/node.srs s1/lex.srs s1/parse.srs s1/check.srs s1/types.srs s1/given.srs s1/facts.srs s1/purity.srs s1/hash.srs s1/eval.srs s1/mono.srs s1/emit.srs s1/lean.srs s1/leanspec.srs s1/store.srs s1/main.srs"
LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/list.lib tests/file.lib"
fail=0
timeout 120 $CCS -o "$B/seed" bootstrap/seed.c rt/srs_rt.c || exit 1
timeout 10 "$B/seed" $S1SRC > "$B/s1.c" && timeout 120 $CCS -o "$B/s1" "$B/s1.c" rt/srs_rt.c || exit 1
timeout 10 "$B/s1" $S1SRC > "$B/s2.c" && timeout 120 $CCS -o "$B/s2" "$B/s2.c" rt/srs_rt.c || exit 1
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
# self tail calls run in constant C stack with no C optimization (vic-m5r.10): tailcall at -O0 (C -O1 hides a missing loop)
timeout 60 $CC -O0 -o "$B/tailcall0" "$B/tailcall.c" rt/srs_rt.c && out=$(timeout 2 "$B/tailcall0") && [ "$out" = "$(cat tests/tailcall.out)" ] && echo "ok tailcall -O0" || { echo "FAIL tailcall -O0"; fail=1; }
# every "// expect: msg" line must be printed: errors are data, main reports them all (vic-ngq); armed: 0 lines = FAIL
for t in tests/neg/*.srs; do
  n=$(basename "$t" .srs)
  msg=$(timeout 2 "$B/s2" $LIBS "$t" 2>&1 >/dev/null); code=$?
  bad=""; [ $code -eq 1 ] || bad=" exit=$code"
  wants=$(sed -n "s|^// expect: ||p" "$t"); [ -n "$wants" ] || bad="$bad no-expect"
  while IFS= read -r want; do case "$msg" in *"$want"*) ;; *) bad="$bad missing=$want";; esac; done <<< "$wants"
  if [ -z "$bad" ]; then echo "ok neg/$n"; else echo "FAIL neg/$n$bad msg=$msg"; fail=1; fi
done
# content hashes (vic-uw3 H1): `s1 --hash` prints "name hash"; each "// same: a b" / "// differ: a b" line must hold
for t in tests/hash/*.srs; do
  n=$(basename "$t" .srs)
  timeout 2 "$B/s2" --hash lib/prelude.srs "$t" > "$B/$n.hash" 2>&1 || { echo "FAIL hash/$n $(head -1 "$B/$n.hash")"; fail=1; continue; }
  bad=""
  # armed: a test with no relation line proves nothing
  [ "$(sed -n 's#^// \(same:\|differ:\) #\1 #p' "$t" | wc -l)" -gt 0 ] || bad=" no-relations"
  while read -r rel a b; do
    ha=$(awk -v n="$a" '$1 == n {print $2}' "$B/$n.hash"); hb=$(awk -v n="$b" '$1 == n {print $2}' "$B/$n.hash")
    if [ -z "$ha" ] || [ -z "$hb" ]; then bad="$bad missing($a $b)"
    elif [ "$rel" = same: ] && [ "$ha" != "$hb" ]; then bad="$bad $a!=$b"
    elif [ "$rel" = differ: ] && [ "$ha" = "$hb" ]; then bad="$bad $a==$b"; fi
  done < <(sed -n 's#^// \(same:\|differ:\) #\1 #p' "$t")
  if [ -n "$bad" ]; then echo "FAIL hash/$n$bad"; fail=1; else echo "ok hash/$n"; fi
done
# the comptime evaluator (vic-u2d.2): `s1 --eval` prints "name value" for each nullary pure def; each
# "// eval: name value" line must be printed; a test whose first line is "// expect: msg" must be rejected with msg
for t in tests/eval/*.srs; do
  n=$(basename "$t" .srs); want=$(sed -n "1s|^// expect: ||p" "$t")
  out=$(timeout 2 "$B/s2" --eval lib/prelude.srs "$t" 2>&1); code=$?
  if [ -n "$want" ]; then
    case "$out" in *"$want"*) [ $code -eq 1 ] && { echo "ok eval/$n"; continue; };; esac
    echo "FAIL eval/$n exit=$code out=$out"; fail=1; continue
  fi
  bad=""; nrel=0
  while read -r name val; do
    nrel=$((nrel + 1))
    printf '%s\n' "$out" | grep -Fxq "$name $val" || bad="$bad $name"
  done < <(sed -n 's#^// eval: ##p' "$t")
  [ $nrel -gt 0 ] || bad=" no-eval-lines"
  if [ $code -ne 0 ] || [ -n "$bad" ]; then echo "FAIL eval/$n exit=$code$bad"; fail=1; else echo "ok eval/$n"; fi
done
# the store (vic-uw3 H2): cold writes every entry, warm writes none, a cut entry reads as bad (a miss)
rm -rf "$SRS_STORE"
st() { timeout 2 "$B/s2" --store-check lib/prelude.srs tests/hash/basic.srs 2>&1; }
cold=$(st); warm=$(st)
e=$(grep -rl I64 "$SRS_STORE" | head -1); cp "$e" "$B/store.keep"
head -c 30 "$B/store.keep" > "$e"; cut=$(st)
# a byte of a name changed (still parses, not equal); bytes after the node (not one whole entry)
sed '0,/I64/s//I65/' "$B/store.keep" > "$e"; flip=$(st)
{ cat "$B/store.keep"; printf 'x'; } > "$e"; trail=$(st)
case "$cold" in "store: wrote "[1-9]*", read equal "[1-9]*", bad 0") ok1=1;; *) ok1=0;; esac
case "$warm" in "store: wrote 0, read equal "[1-9]*", bad 0") ok2=1;; *) ok2=0;; esac
case "$cut$flip$trail" in *", bad 1"*", bad 1"*", bad 1") ok3=1;; *) ok3=0;; esac
if [ $ok1 = 1 ] && [ $ok2 = 1 ] && [ $ok3 = 1 ] && ! cmp -s "$e" "$B/store.keep"; then echo "ok store cold/warm/cut/flip/trail"
else echo "FAIL store cold=[$cold] warm=[$warm] cut=[$cut] flip=[$flip] trail=[$trail]"; fail=1; fi
exit $fail
