#!/usr/bin/env bash
# srs gate, self-hosted (C10): bootstrap/seed.c (srs, C) builds S1; S1 compiles its own src (fixpoint);
# tests/s1/*.srs: S1 compile + run, stdout == .out; tests/s1/neg/*.srs: S1 rejects with "// expect:" text.
# S0 (zig) only when the seed cannot build the src: s0-bootstrap.
set -u
B=${B:-${XDG_RUNTIME_DIR:-/tmp}/srs-build}; mkdir -p "$B"
# tests never touch the user store (vic 2026-11-06): the store of this run lives under $B
export SRS_STORE="$B/store-gate"
CC="zig cc -std=gnu11 -O1 -w"
# the compiler links static on Linux (musl): no dynamic loader per compile (vic-5r9: -13% instr on a small program)
case "$(uname -s)" in Linux) CCS="$CC -static -target $(uname -m)-linux-musl";; *) CCS="$CC";; esac
S1SRC="lib/prelude.srs lib/kanren.srs lib/datalog.srs s1/node.srs s1/lex.srs s1/parse.srs s1/check.srs s1/types.srs s1/given.srs s1/facts.srs s1/purity.srs s1/hash.srs s1/eval.srs s1/mono.srs s1/emit.srs s1/lean.srs s1/leanspec.srs s1/store.srs s1/main.srs"
LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s1/list.lib tests/s1/file.lib"
fail=0
timeout 120 $CCS -o "$B/seed" bootstrap/seed.c rt/srs_rt.c || exit 1
timeout 10 "$B/seed" $S1SRC > "$B/s1.c" && timeout 120 $CCS -o "$B/s1" "$B/s1.c" rt/srs_rt.c || exit 1
timeout 10 "$B/s1" $S1SRC > "$B/s2.c" && timeout 120 $CCS -o "$B/s2" "$B/s2.c" rt/srs_rt.c || exit 1
timeout 10 "$B/s2" $S1SRC > "$B/s3.c" || exit 1
if cmp -s "$B/s2.c" "$B/s3.c"; then echo "ok fixpoint s2.c == s3.c"; else echo "FAIL fixpoint"; fail=1; fi
if cmp -s bootstrap/seed.c "$B/s2.c"; then echo "ok seed == s2.c"; else echo "FAIL seed stale: seed-update"; fail=1; fi
for t in tests/s1/*.srs; do
  n=$(basename "$t" .srs)
  timeout 2 "$B/s2" $LIBS "$t" > "$B/$n.c" || { echo "FAIL $n (s1)"; fail=1; continue; }
  timeout 60 $CC -o "$B/$n" "$B/$n.c" rt/srs_rt.c || { echo "FAIL $n (cc)"; fail=1; continue; }
  out=$(timeout 1 "$B/$n"); code=$?
  if [ $code -ne 0 ] || [ "$out" != "$(cat tests/s1/$n.out)" ]; then echo "FAIL $n exit=$code out=$out"; fail=1; else echo "ok $n"; fi
done
# s2 is functional (vic-m5r.14, vic: "NO `var` everything `val`"): no var, no while, no assignment in s2/*.srs;
# armed: the pattern must hit 3 known bad lines and no good line, else the check proves nothing
FX='^[[:space:]]*(var[[:space:]]|while[[:space:]]|[a-z_][A-Za-z0-9_.]*[[:space:]]*=([^=>]|$))'
armed=$(printf '  var x = 1\n  while c do\n  x = 2\n' | grep -Ec "$FX"); good=$(printf '  val x = 1\n  if x == 2 then a else b\n  case A => b\n' | grep -Ec "$FX")
if [ "$armed" != 3 ] || [ "$good" != 0 ]; then echo "FAIL s2 functional check unarmed ($armed, $good)"; fail=1
elif grep -nE "$FX" s2/*.srs; then echo "FAIL s2 functional: var/while/assignment above"; fail=1
else echo "ok s2 functional (no var, while, assignment)"; fi
# s2 (vic-m5r.13): tests/s2/*.srs compile with the prelude and s2/*.srs only (not the s1 test libs)
S2SRC=$(ls s2/*.srs | tr '\n' ' ')
for t in tests/s2/*.srs; do
  n=s2_$(basename "$t" .srs)
  timeout 2 "$B/s2" lib/prelude.srs $S2SRC "$t" > "$B/$n.c" || { echo "FAIL $n (s1)"; fail=1; continue; }
  timeout 60 $CC -o "$B/$n" "$B/$n.c" rt/srs_rt.c || { echo "FAIL $n (cc)"; fail=1; continue; }
  out=$(timeout 1 "$B/$n"); code=$?
  if [ $code -ne 0 ] || [ "$out" != "$(cat "${t%.srs}.out")" ]; then echo "FAIL $n exit=$code out=$out"; fail=1; else echo "ok $n"; fi
done
# s2 self-host (vic/c/s2-selfhost.md B2, B3): s1 builds s2c; s2c compiles itself to s2c1; s2c1 compiles itself to the
# same C (fixpoint); then s2c1 compiles every tests/s2 program, and each runs with its .out
S2C="lib/prelude.srs $S2SRC s2c/main.srs"
if timeout 5 "$B/s2" $S2C > "$B/s2c0.c" && timeout 120 $CCS -o "$B/s2c0" "$B/s2c0.c" rt/srs_rt.c \
  && timeout 5 "$B/s2c0" $S2C > "$B/s2c1.c" && timeout 120 $CCS -o "$B/s2c1" "$B/s2c1.c" rt/srs_rt.c \
  && timeout 5 "$B/s2c1" $S2C > "$B/s2c2.c" && cmp -s "$B/s2c1.c" "$B/s2c2.c"; then echo "ok s2c fixpoint"
else echo "FAIL s2c fixpoint"; fail=1; fi
for t in tests/s2/*.srs; do
  n=s2c_$(basename "$t" .srs)
  timeout 5 "$B/s2c1" lib/prelude.srs $S2SRC "$t" > "$B/$n.c" || { echo "FAIL $n (s2c)"; fail=1; continue; }
  timeout 60 $CC -o "$B/$n" "$B/$n.c" rt/srs_rt.c || { echo "FAIL $n (cc)"; fail=1; continue; }
  out=$(timeout 1 "$B/$n"); code=$?
  if [ $code -ne 0 ] || [ "$out" != "$(cat "${t%.srs}.out")" ]; then echo "FAIL $n exit=$code out=$out"; fail=1; else echo "ok $n"; fi
done
# the s2 suite (vic 2026-11-09: only s2 survives, tests/s2 stands alone): tests/s2/prog/*.srs compiled by s2c1, run,
# stdout == .out; tests/s2/neg/*.srs rejected by s2c1 (exit 1) with every "// expect:" text. a test named in
# tests/s2/todo is not yet in s2c: it prints "todo", and one that passes is a FAIL (the list only shrinks)
S2LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s2/prog/list.lib tests/s2/prog/file.lib"
todo() { grep -qx "$1" tests/s2/todo; }
verdict() { # name pass
  if todo "$1"; then if [ "$2" = 1 ]; then echo "FAIL $1 passes: remove it from tests/s2/todo"; fail=1; else echo "todo $1"; fi
  elif [ "$2" = 1 ]; then echo "ok $1"; else echo "FAIL $1 $3"; fail=1; fi
}
for t in tests/s2/prog/*.srs; do
  n=$(basename "$t" .srs); m=s2c1_$n; pass=0
  timeout 5 "$B/s2c1" $S2LIBS "$t" > "$B/$m.c" 2>/dev/null && timeout 60 $CC -o "$B/$m" "$B/$m.c" rt/srs_rt.c 2>/dev/null \
    && out=$(timeout 1 "$B/$m") && [ "$out" = "$(cat tests/s2/prog/$n.out)" ] && pass=1
  verdict "prog/$n" $pass
done
for t in tests/s2/neg/*.srs; do
  n=$(basename "$t" .srs); pass=1
  msg=$(timeout 2 "$B/s2c1" $S2LIBS "$t" 2>&1 >/dev/null); code=$?
  wants=$(sed -n "s|^// expect: ||p" "$t"); [ $code -eq 1 ] && [ -n "$wants" ] || pass=0
  while IFS= read -r w; do case "$msg" in *"$w"*) ;; *) pass=0;; esac; done <<< "$wants"
  verdict "neg/$n" $pass "exit=$code msg=$(printf '%s' "$msg" | head -1)"
done
# s2c --eval (the comptime evaluator): each "// eval: name value" line is printed; a test whose first line is
# "// expect: msg" is rejected (exit 1) with msg; a test with neither proves nothing (FAIL)
for t in tests/s2/eval/*.srs; do
  n=$(basename "$t" .srs); pass=1
  out=$(timeout 2 "$B/s2c1" --eval lib/prelude.srs "$t" 2>&1); code=$?
  want=$(sed -n "1s|^// expect: ||p" "$t"); evals=$(sed -n 's#^// eval: ##p' "$t")
  if [ -n "$want" ]; then case "$out" in *"$want"*) [ $code -eq 1 ] || pass=0;; *) pass=0;; esac
  elif [ -z "$evals" ] || [ $code -ne 0 ]; then pass=0
  else while IFS= read -r line; do printf '%s\n' "$out" | grep -Fxq "$line" || pass=0; done <<< "$evals"; fi
  verdict "eval/$n" $pass "exit=$code out=$(printf '%s' "$out" | head -1)"
done
# s2c errors are data: a clash is printed on stderr, no C, exit 1
printf 'def main(): I64 = true\n' > "$B/s2c_bad.srs"
msg=$(timeout 2 "$B/s2c1" lib/prelude.srs "$B/s2c_bad.srs" 2>&1 >"$B/s2c_bad.c"); code=$?
if [ $code -eq 1 ] && [ "$msg" = "line 1: type mismatch" ] && [ ! -s "$B/s2c_bad.c" ]; then echo "ok s2c clash exit 1"; else echo "FAIL s2c clash exit=$code msg=$msg"; fail=1; fi
# type level errors are data too: a looping alias runs out of fuel, a value match with no case for its arg is a reject
printf 'type Loop = Loop\ndef main(): Loop = 0\n' > "$B/s2c_tl1.srs"
printf 'type W (n: I64) = n match\n  case 1 => I64\ndef main(): W(2) = 0\n' > "$B/s2c_tl2.srs"
m1=$(timeout 2 "$B/s2c1" lib/prelude.srs "$B/s2c_tl1.srs" 2>&1 >/dev/null); c1=$?
m2=$(timeout 2 "$B/s2c1" lib/prelude.srs "$B/s2c_tl2.srs" 2>&1 >/dev/null); c2=$?
if [ $c1 -eq 1 ] && [ "$m1" = "line 1: type reduction ran out of fuel at Loop" ] && [ $c2 -eq 1 ] && [ "$m2" = "line 3: no case of the match type matches in W" ]; then echo "ok s2c type level errors"
else echo "FAIL s2c type level errors $c1 $m1 / $c2 $m2"; fail=1; fi
# s2c self tail calls loop: coll folds a 1M list, at -O0 (C -O1 hides a missing loop)
timeout 60 $CC -O0 -o "$B/s2c_coll0" "$B/s2c_coll.c" rt/srs_rt.c && out=$(timeout 2 "$B/s2c_coll0") && [ "$out" = "$(cat tests/s2/coll.out)" ] && echo "ok s2c tailcall -O0" || { echo "FAIL s2c tailcall -O0"; fail=1; }
# self tail calls run in constant C stack with no C optimization (vic-m5r.10): tailcall at -O0 (C -O1 hides a missing loop)
timeout 60 $CC -O0 -o "$B/tailcall0" "$B/tailcall.c" rt/srs_rt.c && out=$(timeout 2 "$B/tailcall0") && [ "$out" = "$(cat tests/s1/tailcall.out)" ] && echo "ok tailcall -O0" || { echo "FAIL tailcall -O0"; fail=1; }
# every "// expect: msg" line must be printed: errors are data, main reports them all (vic-ngq); armed: 0 lines = FAIL
for t in tests/s1/neg/*.srs; do
  n=$(basename "$t" .srs)
  msg=$(timeout 2 "$B/s2" $LIBS "$t" 2>&1 >/dev/null); code=$?
  bad=""; [ $code -eq 1 ] || bad=" exit=$code"
  wants=$(sed -n "s|^// expect: ||p" "$t"); [ -n "$wants" ] || bad="$bad no-expect"
  while IFS= read -r want; do case "$msg" in *"$want"*) ;; *) bad="$bad missing=$want";; esac; done <<< "$wants"
  if [ -z "$bad" ]; then echo "ok neg/$n"; else echo "FAIL neg/$n$bad msg=$msg"; fail=1; fi
done
# content hashes (vic-uw3 H1): `s1 --hash` prints "name hash"; each "// same: a b" / "// differ: a b" line must hold
for t in tests/s1/hash/*.srs; do
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
for t in tests/s1/eval/*.srs; do
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
st() { timeout 2 "$B/s2" --store-check lib/prelude.srs tests/s1/hash/basic.srs 2>&1; }
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
