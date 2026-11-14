#!/bin/bash
# T-c (TYPES-1b, the C type of every local). bash tests/s3/types/tc.sh <s3c> (run from the repo root)
#  `s3c --types-locals Y1` prints one C file: a prelude (srs_str, srs_cap), per non-generic def `static void d_N(<params>) { T v_x_J = {0};
#  ... T w_N_K = <local>; }` and the struct forward declarations. v_x_J is a local (J = its binder token): its C type is the one
#  s3c computed, explicit (no __auto_type). w_N_K is a witness: a local that the program passes as an arg of a call, copied into a variable
#  of the callee's param type: it compiles only when the two C types fit. bar: `zig cc -c -std=c11 -Werror -Wall` = 0 diagnostics, and
#  locals >= 10000, witnesses >= 10000. Generic defs (96) are counted as skipped, not silently: their locals belong to their instances.
#  armed: one local that is a witness is flipped by awk in a copy of the file (an int64_t becomes a struct pointer): the compile must then
#  FAIL; the flipped line is checked to have changed (count before / after: 0 -> 1). Not-unused-function is off: the d_N are never called.
. tests/s3/lib.sh
init T-c "$1"
num() { printf '%s\n' "$1" | sed -n "s/.* $2=\([0-9]*\).*/\1/p" | head -1; }
timeout 60 "$BIN" --types-locals $Y1 > "$T/loc.txt"
sum=$(grep '^// locals:' "$T/loc.txt" | head -1)
echo "$sum"
mk=$(grep -n '^// forward declarations' "$T/loc.txt" | head -1 | cut -d: -f1)
[ -n "$mk" ] || bad "no forward declaration marker"
# the C file: the 4 prelude lines, the forward declarations, then the defs
awk -v m="$mk" 'NR<=4{print; next} NR>m && !/^\/\//{f[++nf]=$0; next} NR>4 && NR<m{d[++nd]=$0} END{for(i=1;i<=nf;i++)print f[i]; for(i=1;i<=nd;i++)print d[i]}' "$T/loc.txt" > "$T/loc.c"
CC="zig cc -c -o /dev/null -std=c11 -Werror -Wall -Wno-unused-variable -Wno-unused-but-set-variable -Wno-unused-parameter -Wno-unused-function"
timeout 120 $CC "$T/loc.c" > "$T/cc.txt" 2>&1; rc=$?
nd=$(grep -c 'error' "$T/cc.txt")
loc=$(num "$sum" locals); wit=$(num "$sum" witnesses); ws=$(num "$sum" witnessesskipped); lb=$(num "$sum" localsunprinted); defs=$(num "$sum" defs); dsk=$(num "$sum" defsskipped)
echo "cc exit=$rc diagnostics=$nd lines=$(wc -l < "$T/loc.c")"
head -5 "$T/cc.txt" | cut -c1-200
[ $rc = 0 ] && [ "$nd" = 0 ] || bad "cc exit=$rc diagnostics=$nd (want 0)"
[ "${loc:-0}" -ge 10000 ] && [ "${wit:-0}" -ge 10000 ] || bad "locals=$loc witnesses=$wit (want >= 10000 each)"
[ "${lb:-1}" = 0 ] || bad "localsunprinted=$lb (want 0: a local with no ground type)"
# armed: flip the first I64 witness local (declared once as `int64_t v_..`): it becomes a struct pointer
flip=""
for cand in $(grep -n '^int64_t w_[0-9]*_[0-9]* = v_' "$T/loc.c" | head -50 | sed 's/.* = \(v_[A-Za-z0-9_]*\);.*/\1/'); do
  n=$(grep -c "^int64_t $cand = {0};" "$T/loc.c")
  if [ "$n" = 1 ]; then flip=$cand; break; fi
done
[ -n "$flip" ] || bad "armed: no int64_t witness local found"
before=$(grep -c "^struct E_Flip\* $flip = {0};" "$T/loc.c")
awk -v v="$flip" '$0 == "int64_t " v " = {0};" {print "struct E_Flip* " v " = {0};"; next} {print}' "$T/loc.c" > "$T/mut.c"
after=$(grep -c "^struct E_Flip\* $flip = {0};" "$T/mut.c")
echo "armed: local $flip flipped int64_t -> struct E_Flip* (lines before=$before after=$after)"
[ "$before" = 0 ] && [ "$after" = 1 ] || bad "armed: the flip did not change exactly one line"
timeout 120 $CC "$T/mut.c" > "$T/ccm.txt" 2>&1; mrc=$?
mn=$(grep -c 'error' "$T/ccm.txt")
echo "armed: cc exit=$mrc diagnostics=$mn (want a failure)"
head -3 "$T/ccm.txt" | cut -c1-200
[ $mrc != 0 ] && [ "$mn" -ge 1 ] || bad "not armed: the flipped local still compiles"
NAME="T-c locals=$loc witnesses=$wit diagnostics=$nd defs=$defs generic-skipped=$dsk"
finish
