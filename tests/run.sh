#!/usr/bin/env bash
# srs gate (s2 only; vic 2026-11-09): bootstrap/s2c-seed.c builds s2c; s2c compiles itself (fixpoint, seed fresh); then
# tests/s2: the s2 component tests, prog (compile, run, == .out), neg (rejected with the expected error[code] and
# location), eval, hash, store, tail calls at -O0. no s0 or s1 on any path.
set -u
B=${B:-${XDG_RUNTIME_DIR:-/tmp}/srs-build}; mkdir -p "$B"
# tests never touch the user store (vic 2026-11-06): the store of this run lives under $B
export SRS_STORE="$B/store-gate"
CC="zig cc -std=gnu11 -O1 -w"
# the compiler links static on Linux (musl): no dynamic loader per compile (vic-5r9: -13% instr on a small program)
case "$(uname -s)" in Linux) CCS="$CC -static -target $(uname -m)-linux-musl";; *) CCS="$CC";; esac
fail=0
# s2 is functional (vic-m5r.14, vic: "NO `var` everything `val`"): no var, no while, no assignment in s2/*.srs;
# armed: the pattern must hit 3 known bad lines and no good line, else the check proves nothing
FX='^[[:space:]]*(var[[:space:]]|while[[:space:]]|[a-z_][A-Za-z0-9_.]*[[:space:]]*=([^=>]|$))'
armed=$(printf '  var x = 1\n  while c do\n  x = 2\n' | grep -Ec "$FX"); good=$(printf '  val x = 1\n  if x == 2 then a else b\n  case A => b\n' | grep -Ec "$FX")
if [ "$armed" != 3 ] || [ "$good" != 0 ]; then echo "FAIL s2 functional check unarmed ($armed, $good)"; fail=1
elif grep -nE "$FX" s2/*.srs; then echo "FAIL s2 functional: var/while/assignment above"; fail=1
else echo "ok s2 functional (no var, while, assignment)"; fi
S2SRC=$(ls s2/*.srs | tr '\n' ' ')
# s2 self-host (vic/c/s2-selfhost.md B2, B3): bootstrap/s2c-seed.c (s2c's own C) builds s2c0; s2c0 compiles s2c to
# s2c1.c, which must be the seed (else seed-update); s2c1 compiles itself to the same C (fixpoint); then s2c1
# compiles every tests/s2 program. no s0 or s1 on this path
S2C="lib/prelude.srs $S2SRC s2c/main.srs"
if timeout 120 $CCS -o "$B/s2c0" bootstrap/s2c-seed.c rt/srs_rt.c \
  && timeout 5 "$B/s2c0" $S2C > "$B/s2c1.c" && timeout 120 $CCS -o "$B/s2c1" "$B/s2c1.c" rt/srs_rt.c \
  && timeout 5 "$B/s2c1" $S2C > "$B/s2c2.c" && cmp -s "$B/s2c1.c" "$B/s2c2.c"; then echo "ok s2c fixpoint"
else echo "FAIL s2c fixpoint"; fail=1; fi
if cmp -s bootstrap/s2c-seed.c "$B/s2c1.c"; then echo "ok s2c seed == s2c1.c"; else echo "FAIL s2c seed stale: seed-update"; fail=1; fi
# the test loops run in parallel (xargs -P, GATE_JOBS at once, default one per core): each test is a fn of its file that
# prints its verdict line(s) into its own file; par prints them in file order, so the log reads as a serial run's. A
# test fn that exits nonzero (killed, crashed) is a FAIL line, and par fails when any line is a FAIL
GATE_JOBS=${GATE_JOBS:-$(nproc)}
export B S2SRC CC
par() { # fn files...
  local f=$1 d i=0 x; shift; d=$(mktemp -d "$B/par.XXXXXX")
  for x in "$@"; do i=$((i + 1)); printf '%s\0%s\0' "$d/$i" "$x"; done \
    | xargs -0 -n2 -P "$GATE_JOBS" bash -c "$f \"\$2\" > \"\$1\" 2>&1 || echo \"FAIL $f \$2 (exit \$?)\" >> \"\$1\"" _ \
    || echo "FAIL $f: a test process died (xargs exit $?)" > "$d/died"
  i=0; for x in "$@"; do i=$((i + 1)); cat "$d/$i" 2>/dev/null; done > "$d/all"; cat "$d/died" >> "$d/all" 2>/dev/null
  cat "$d/all"; ! grep -q '^FAIL' "$d/all"
}
t_comp() {
  local t=$1 n out code; n=s2c_$(basename "$t" .srs)
  timeout 5 "$B/s2c1" lib/prelude.srs $S2SRC "$t" > "$B/$n.c" || { echo "FAIL $n (s2c)"; return 0; }
  timeout 60 $CC -o "$B/$n" "$B/$n.c" rt/srs_rt.c || { echo "FAIL $n (cc)"; return 0; }
  out=$(timeout 1 "$B/$n"); code=$?
  if [ $code -ne 0 ] || [ "$out" != "$(cat "${t%.srs}.out")" ]; then echo "FAIL $n exit=$code out=$out"; else echo "ok $n"; fi
}
export -f t_comp
par t_comp tests/s2/*.srs || fail=1
# the s2 suite (vic 2026-11-09: only s2 survives, tests/s2 stands alone): tests/s2/prog/*.srs compiled by s2c1, run,
# stdout == .out; tests/s2/neg/*.srs rejected by s2c1 (exit 1) with every "// expect:" text. a test named in
# tests/s2/todo is not yet in s2c: it prints "todo", and one that passes is a FAIL (the list only shrinks)
S2LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s2/prog/list.lib tests/s2/prog/file.lib"
todo() { grep -qx "$1" tests/s2/todo; }
verdict() { # name pass
  if todo "$1"; then if [ "$2" = 1 ]; then echo "FAIL $1 passes: remove it from tests/s2/todo"; fail=1; else echo "todo $1"; fi
  elif [ "$2" = 1 ]; then echo "ok $1"; else echo "FAIL $1 $3"; fail=1; fi
}
export S2LIBS
export -f todo verdict
# a "// env: A=1 B=" line: the program runs with those variables set (os_env, stack_deep)
t_prog() {
  local t=$1 n m pass=0 out; n=$(basename "$t" .srs); m=s2c1_$n
  timeout 5 "$B/s2c1" $S2LIBS "$t" > "$B/$m.c" 2>/dev/null && timeout 60 $CC -o "$B/$m" "$B/$m.c" rt/srs_rt.c $(sed -n 's|^// c: ||p' "$t") 2>/dev/null \
    && out=$(env $(sed -n 's|^// env: ||p' "$t") timeout 1 "$B/$m") && [ "$out" = "$(cat tests/s2/prog/$n.out)" ] && pass=1
  verdict "prog/$n" $pass
}
export -f t_prog
par t_prog tests/s2/prog/*.srs || fail=1
# stdout is bounded at 1 MiB (vic-xg9m): prog/out_big prints 2.4 MB and must reach the fd in more than one write
ST=$(command -v strace || timeout 120 nix-shell -p strace --run 'command -v strace' 2>/dev/null)
w=$( [ -x "${ST:-}" ] && timeout 10 "$ST" -f -c -e trace=write "$B/s2c1_out_big" 2>&1 >/dev/null | awk '$NF == "write" {print $4}')
if [ ! -x "${ST:-}" ]; then echo "FAIL prog/out_big: strace missing"; fail=1
elif [ "${w:-0}" -gt 1 ]; then echo "ok prog/out_big writes $w"; else echo "FAIL prog/out_big writes ${w:-none}, want > 1"; fail=1; fi
# Arena chunks are advised for huge pages only when main installs Srs.Pages: prog/alloc_chunks (no Pages) fills more than one 1 MiB chunk and gets
# no advice, prog/pages_gate (Pages) fills three reservations and gets some while the gate is On
h=$( [ -x "${ST:-}" ] && timeout 10 "$ST" -e trace=madvise "$B/s2c1_alloc_chunks" 2>&1 >/dev/null | grep -c MADV_HUGEPAGE)
if [ "${h:-0}" -eq 0 ]; then echo "ok prog/alloc_chunks no advice without Pages"; else echo "FAIL prog/alloc_chunks advised $h without Pages"; fail=1; fi
h=$( [ -x "${ST:-}" ] && timeout 10 "$ST" -e trace=madvise "$B/s2c1_pages_gate" 2>&1 >/dev/null | grep -c MADV_HUGEPAGE)
if [ "${h:-0}" -ge 1 ]; then echo "ok prog/pages_gate huge-page advice $h"; else echo "FAIL prog/pages_gate no MADV_HUGEPAGE"; fail=1; fi
# s2c's main installs Srs.Pages: compiling itself touches ~190 MB, 47k faults at 4 KiB pages, ~550 with huge pages
h=$( [ -x "${ST:-}" ] && timeout 10 "$ST" -e trace=madvise "$B/s2c1" $S2C 2>&1 >/dev/null | grep -c MADV_HUGEPAGE)
if [ "${h:-0}" -ge 1 ]; then echo "ok s2c huge-page advice $h"; else echo "FAIL s2c no MADV_HUGEPAGE: main must handle Srs.Pages"; fail=1; fi
t_neg() {
  local t=$1 n pass=1 msg code wants w; n=$(basename "$t" .srs)
  msg=$(timeout 2 "$B/s2c1" $S2LIBS "$t" 2>&1 >/dev/null); code=$?
  wants=$(sed -n "s|^// expect: ||p" "$t"); [ $code -eq 1 ] && [ -n "$wants" ] || pass=0
  # "error[code]" is in the message; "--> file:line" is a whole line of it (so :1 does not match :12)
  while IFS= read -r w; do
    case "$w" in
      "-->"*) printf '%s\n' "$msg" | sed 's/^ *//' | grep -Fxq -- "$w" || pass=0;;
      *) case "$msg" in *"$w"*) ;; *) pass=0;; esac;;
    esac
  done <<< "$wants"
  verdict "neg/$n" $pass "exit=$code msg=$(printf '%s' "$msg" | head -1)"
}
export -f t_neg
par t_neg tests/s2/neg/*.srs || fail=1
# tests/s2/cneg/*.srs: s2c1 accepts them (exit 0) and the C compiler rejects the C with every "// expect:" text: the libc
# headers make the C compiler check each srs prototype of a libc extern (C11 6.7p4)
t_cneg() {
  local t=$1 n pass=1 m msg code wants w; n=$(basename "$t" .srs); m=cneg_$n
  timeout 5 "$B/s2c1" $S2LIBS "$t" > "$B/$m.c" 2>/dev/null || pass=0
  msg=$(timeout 60 $CC -o "$B/$m" "$B/$m.c" rt/srs_rt.c 2>&1); code=$?
  wants=$(sed -n "s|^// expect: ||p" "$t"); [ $code -ne 0 ] && [ -n "$wants" ] || pass=0
  while IFS= read -r w; do case "$msg" in *"$w"*) ;; *) pass=0;; esac; done <<< "$wants"
  verdict "cneg/$n" $pass "cc exit=$code msg=$(printf '%s' "$msg" | head -1)"
}
export -f t_cneg
par t_cneg tests/s2/cneg/*.srs || fail=1
# the Flow shortcut (Flow.plainFn, vic-6z7p.30): every program of prog/ neg/ and the component tests is compiled with --l2-agree: a fn the shortcut
# skips is also checked by the engine, and any disagreement prints L2-UNSOUND (the soundness argument is tests/s2/flow_seeds.srs)
bad=0
t_l2() { if timeout 10 "$B/s2c1" --l2-agree $S2LIBS "$1" 2>&1 >/dev/null | grep -q 'L2-UNSOUND'; then echo "FAIL l2-agree $1"; fi; }
export -f t_l2
par t_l2 tests/s2/prog/*.srs tests/s2/neg/*.srs || bad=1
if timeout 60 "$B/s2c1" --l2-agree $S2C 2>&1 >/dev/null | grep -q 'L2-UNSOUND'; then echo "FAIL l2-agree s2c sources"; bad=1; fi
if [ $bad -eq 0 ]; then echo "ok l2-agree"; else fail=1; fi
# tests/s2/cok/*.srs: s2c1 accepts them and the C compiler accepts the C (built, never run): our prototype of each libc extern
# agrees with the real declaration in the libc headers (C11 6.7p4)
t_cok() {
  local t=$1 n pass=1 m msg; n=$(basename "$t" .srs); m=cok_$n
  timeout 5 "$B/s2c1" $S2LIBS "$t" > "$B/$m.c" 2>/dev/null || pass=0
  msg=$(timeout 60 $CC -o "$B/$m" "$B/$m.c" rt/srs_rt.c 2>&1) || pass=0
  verdict "cok/$n" $pass "cc msg=$(printf '%s' "$msg" | head -1)"
}
export -f t_cok
par t_cok tests/s2/cok/*.srs || fail=1
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
# s2c --hash (content hashes): each "// same: a b" / "// differ: a b" holds, each "// golden: name a.b.c.d" is that exact digest; a test with no relation proves nothing
for t in tests/s2/hash/*.srs; do
  n=$(basename "$t" .srs); pass=1; out=$(timeout 2 "$B/s2c1" --hash lib/prelude.srs "$t" 2>&1) || pass=0
  rels=$(sed -n 's#^// \(same:\|differ:\|golden:\) #\1 #p' "$t"); [ -n "$rels" ] || pass=0
  while read -r rel a b; do
    ha=$(printf '%s\n' "$out" | awk -v n="$a" '$1 == n {print $2}'); hb=$(printf '%s\n' "$out" | awk -v n="$b" '$1 == n {print $2}')
    if [ "$rel" = golden: ]; then [ "$ha" = "$b" ] || pass=0; continue; fi
    if [ -z "$ha" ] || [ -z "$hb" ]; then pass=0; elif [ "$rel" = same: ] && [ "$ha" != "$hb" ]; then pass=0; elif [ "$rel" = differ: ] && [ "$ha" = "$hb" ]; then pass=0; fi
  done <<< "$rels"
  verdict "hash/$n" $pass
done
# s2c --store-check (its own store under $B): cold writes every entry, warm writes none; a cut entry, a changed byte and
# a trailing byte each read as bad (a miss)
S2STORE="$B/store-s2"; rm -rf "$S2STORE"
sst() { SRS_STORE="$S2STORE" timeout 2 "$B/s2c1" --store-check lib/prelude.srs tests/s2/hash/basic.srs 2>&1; }
cold=$(sst); warm=$(sst)
e=$(grep -rl I64 "$S2STORE" | head -1); cp "$e" "$B/store-s2.keep"
head -c -2 "$B/store-s2.keep" > "$e"; cut=$(sst)
sed '0,/I64/s//I65/' "$B/store-s2.keep" > "$e"; flip=$(sst)
{ cat "$B/store-s2.keep"; printf 'x'; } > "$e"; trail=$(sst)
case "$cold" in "store: wrote "[1-9]*", read equal "[1-9]*", bad 0") ok1=1;; *) ok1=0;; esac
case "$warm" in "store: wrote 0, read equal "[1-9]*", bad 0") ok2=1;; *) ok2=0;; esac
case "$cut$flip$trail" in *", bad 1"*", bad 1"*", bad 1") ok3=1;; *) ok3=0;; esac
if [ $ok1 = 1 ] && [ $ok2 = 1 ] && [ $ok3 = 1 ] && ! cmp -s "$e" "$B/store-s2.keep"; then echo "ok s2c store cold/warm/cut/flip/trail"
else echo "FAIL s2c store cold=[$cold] warm=[$warm] cut=[$cut] flip=[$flip] trail=[$trail]"; fail=1; fi
# s2c errors are data: a clash is printed on stderr, no C, exit 1
printf 'def main(): I64 = true\n' > "$B/s2c_bad.srs"
msg=$(timeout 2 "$B/s2c1" lib/prelude.srs "$B/s2c_bad.srs" 2>&1 >"$B/s2c_bad.c"); code=$?
if [ $code -eq 1 ] && [ "$(printf '%s\n' "$msg" | head -1)" = "error[mismatch]: the value has the wrong type" ] && [ ! -s "$B/s2c_bad.c" ]; then echo "ok s2c clash exit 1"; else echo "FAIL s2c clash exit=$code msg=$msg"; fail=1; fi
# type level errors are data too: a looping alias runs out of fuel, a value match with no case for its arg is a reject
printf 'type Loop = Loop\ndef main(): Loop = 0\n' > "$B/s2c_tl1.srs"
printf 'type W (n: I64) = n match\n  case 1 => I64\ndef main(): W(2) = 0\n' > "$B/s2c_tl2.srs"
m1=$(timeout 2 "$B/s2c1" lib/prelude.srs "$B/s2c_tl1.srs" 2>&1 >/dev/null); c1=$?
m2=$(timeout 2 "$B/s2c1" lib/prelude.srs "$B/s2c_tl2.srs" 2>&1 >/dev/null); c2=$?
if [ $c1 -eq 1 ] && [ "$(printf '%s\n' "$m1" | head -1)" = "error[type-fuel]: type reduction ran out of fuel at 'Loop'" ] && [ $c2 -eq 1 ] && [ "$(printf '%s\n' "$m2" | head -1)" = "error[no-type-case]: no case of the match type matches in 'W'" ]; then echo "ok s2c type level errors"
else echo "FAIL s2c type level errors $c1 $m1 / $c2 $m2"; fail=1; fi
# s2c self tail calls loop: coll folds a 1M list, at -O0 (C -O1 hides a missing loop)
timeout 60 $CC -O0 -o "$B/s2c_coll0" "$B/s2c_coll.c" rt/srs_rt.c && out=$(timeout 2 "$B/s2c_coll0") && [ "$out" = "$(cat tests/s2/coll.out)" ] && echo "ok s2c tailcall -O0" || { echo "FAIL s2c tailcall -O0"; fail=1; }
timeout 60 $CC -O0 -o "$B/s2c1_tailcall0" "$B/s2c1_tailcall.c" rt/srs_rt.c && out=$(timeout 2 "$B/s2c1_tailcall0") && [ "$out" = "$(cat tests/s2/prog/tailcall.out)" ] && echo "ok s2c prog tailcall -O0" || { echo "FAIL s2c prog tailcall -O0"; fail=1; }
# words are total in C (U32, U64): prog/bits under shift and signed-overflow traps; a shift count not taken mod the
# width is C undefined behavior, and x86 masks it silently, so the plain run cannot see it
timeout 60 $CC -fsanitize=shift,signed-integer-overflow -fsanitize-trap=shift,signed-integer-overflow -o "$B/s2c1_bits_ub" "$B/s2c1_bits.c" rt/srs_rt.c && out=$(timeout 1 "$B/s2c1_bits_ub") && [ "$out" = "$(cat tests/s2/prog/bits.out)" ] && echo "ok s2c prog bits under UB traps" || { echo "FAIL s2c prog bits under UB traps"; fail=1; }
# static capabilities (s2/emit.srs Emit.staticsOf): main's one Console handle leaves no Console param in the rows;
# a nested second Console handle, or a call of main, keeps the param
if ! grep -q 'srs_cap\* p_eff__Console' "$B/s2c1_cap_static.c" && grep -q '^static srs_cap s_eff__Console = ' "$B/s2c1_cap_static.c"; then echo "ok s2c static Console: no param"; else echo "FAIL s2c static Console: param kept"; fail=1; fi
if grep -q 'srs_cap\* p_eff__Console' "$B/s2c1_cap_nested.c" && ! grep -q 's_eff__Console' "$B/s2c1_cap_nested.c"; then echo "ok s2c nested Console: param kept"; else echo "FAIL s2c nested Console: made static"; fail=1; fi
if grep -q 'srs_cap\* p_eff__Console' "$B/s2c1_cap_main_call.c" && ! grep -q 's_eff__Console' "$B/s2c1_cap_main_call.c"; then echo "ok s2c main called: param kept"; else echo "FAIL s2c main called: made static"; fail=1; fi
# Region (Srs.Arena or Srs.Heap) is static when it has one handle in main and no written {r: Region} binder: no row takes a
# Region param. two Arenas, a named region f{r}(x), or a nested sub-region keep the param in every row. (handler fns keep
# their params, so the grep is on the rows f_*). compiled with the prelude alone: tests/s2/prog/list.lib writes a {r: Region}
# binder, which keeps the param in every program that loads it. each is also run: its output must be its .out
rowreg='f_[A-Za-z0-9_]*(srs_cap\* p_eff__Region'
for n in one heap bytes two named nested handler trait traitg given givenfn; do
  t=tests/s2/prog/cap_region_$n; c="$B/s2c_rg_$n.c"
  if timeout 5 "$B/s2c1" lib/prelude.srs "$t.srs" > "$c" && timeout 60 $CC -o "$B/s2c_rg_$n" "$c" rt/srs_rt.c && [ "$(timeout 1 "$B/s2c_rg_$n")" = "$(cat "$t.out")" ]; then
    case $n in
      one|heap|bytes) if ! grep -q "$rowreg" "$c" && grep -q '^static srs_cap s_eff__Region = ' "$c"; then echo "ok s2c static Region $n: no param"; else echo "FAIL s2c static Region $n: param kept"; fail=1; fi;;
      *) if grep -q "$rowreg" "$c" && ! grep -q 's_eff__Region' "$c"; then echo "ok s2c Region $n: param kept"; else echo "FAIL s2c Region $n: made static"; fail=1; fi;;
    esac
  else echo "FAIL s2c Region $n (build or output)"; fail=1; fi
done
# the C fragment gate (s2/elgate.srs, vic-de9x.1 X1): s2c and the table of --fragment. s2c itself has no violation of a
# permanent kind (fn-ptr-call, exit), so --fragment exits 0 on it; the table lists the other kinds (stmt-expr,
# auto-type, goto-out, address-of) as report-only until emit stops producing them. armed: each tests/s2/frag program has
# one permanent violation, so --fragment exits 1 with its "// expect:" line
out=$(timeout 60 "$B/s2c1" --fragment $S2C 2>&1); code=$?
if [ $code -eq 0 ] && printf '%s\n' "$out" | grep -q '^stmt-expr'; then echo "ok s2c fragment gate: s2c has no permanent-kind violation"; else echo "FAIL s2c fragment gate exit=$code: $(printf '%s' "$out" | head -3)"; fail=1; fi
for t in tests/s2/frag/*.srs; do
  n=$(basename "$t" .srs); pass=1
  msg=$(timeout 5 "$B/s2c1" --fragment $S2LIBS "$t" 2>&1 >/dev/null); code=$?
  wants=$(sed -n "s|^// expect: ||p" "$t"); [ $code -eq 1 ] && [ -n "$wants" ] || pass=0
  while IFS= read -r w; do case "$msg" in *"$w"*) ;; *) pass=0;; esac; done <<< "$wants"
  verdict "frag/$n" $pass "exit=$code msg=$(printf '%s' "$msg" | head -1)"
done
# the ratchet (tests/s2/fragment.base): per input, the count of each report-only kind (stmt-expr, auto-type, goto-out,
# address-of) may not grow, and a decrease must update the base in the same change. inputs: the frozen bench corpus and
# s2c's own source. armed: tiny_grow.srs (tiny.srs + one extra match) fails against the "tiny" row, and a lowered base
# row fails too
frag_ratchet() { # name base fragment-output: one line per cell that differs; exit 1 when any
  local name=$1 base=$2 out=$3 rc=0 k n b
  for k in stmt-expr auto-type goto-out address-of; do
    n=$(printf '%s\n' "$out" | awk -F'\t' -v k="$k" '$1 == k {s += $3} END {print s + 0}')
    b=$(awk -v i="$name" -v k="$k" '$1 == i && $2 == k {print $3}' "$base")
    if [ -z "$b" ]; then echo "$name $k: no row in $base"; rc=1
    elif [ "$n" -gt "$b" ]; then echo "$name $k grew $b -> $n"; rc=1
    elif [ "$n" -lt "$b" ]; then echo "$name $k shrank $b -> $n: update tests/s2/fragment.base in this change"; rc=1; fi
  done
  return $rc
}
FB=tests/s2/fragment.base
CSRCF="bench/corpus/lib/prelude.srs $(ls bench/corpus/s2/*.srs | tr '\n' ' ') bench/corpus/s2c/main.srs"
for pair in "corpus:$CSRCF" "s2c:$S2C" "tiny:lib/prelude.srs tests/s2/fragbase/tiny.srs"; do
  name=${pair%%:*}; out=$(timeout 60 "$B/s2c1" --fragment ${pair#*:} 2>/dev/null); msg=$(frag_ratchet "$name" "$FB" "$out"); code=$?
  # s2c rows only report: s2c's own source moves with every s2 edit, so the corpus and tiny rows are the ratchet
  if [ $code -eq 0 ]; then echo "ok fragment ratchet $name"
  elif [ "$name" = s2c ]; then echo "info fragment s2c (report only): $(printf '%s' "$msg" | tr '\n' ';')"
  else echo "FAIL fragment ratchet $name: $(printf '%s' "$msg" | head -2 | tr '\n' ';')"; fail=1; fi
done
out=$(timeout 10 "$B/s2c1" --fragment lib/prelude.srs tests/s2/fragbase/tiny_grow.srs 2>/dev/null); msg=$(frag_ratchet tiny "$FB" "$out"); code=$?
case "$msg" in *"stmt-expr grew"*) [ $code -eq 1 ] && echo "ok fragment ratchet armed: one extra match grows stmt-expr" || { echo "FAIL fragment ratchet armed (grow)"; fail=1; };; *) echo "FAIL fragment ratchet armed (grow): $msg"; fail=1;; esac
awk '$1 == "tiny" && $2 == "stmt-expr" {$3 = $3 + 1} {print}' "$FB" > "$B/fragment.low"
out=$(timeout 10 "$B/s2c1" --fragment lib/prelude.srs tests/s2/fragbase/tiny.srs 2>/dev/null); msg=$(frag_ratchet tiny "$B/fragment.low" "$out"); code=$?
case "$msg" in *"stmt-expr shrank"*) [ $code -eq 1 ] && echo "ok fragment ratchet armed: a decrease needs a base update" || { echo "FAIL fragment ratchet armed (shrink)"; fail=1;};; *) echo "FAIL fragment ratchet armed (shrink): $msg"; fail=1;; esac
exit $fail
