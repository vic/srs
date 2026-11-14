#!/bin/bash
# T-l (S1a, the length index of Array[A](n) in the interned type id). bash tests/s3/types/tl.sh <s3c> (run from the repo root)
#  The length of Array[A](n) is the last arg of the interned type id (kind Len, an exact key: a literal, or a binder = (file, token); no Any).
#  1. the planted programs of tests/s3/types/len (line 1 = `// expect: error[lengthNotName]` | `error[mismatch]` | `ok`, the last line =
#     `// expect: --> FILE:LINE`), each typed as `s3c --types lib/prelude.srs FILE`:
#     n1 compound, n2 call, n3 global constant, n6 var, n7 assigned later, n8 assigned param  -> `lengthNotName FILE:LINE`
#     n4 shadowed binder, n5 swapped binders, n9 / n10 a literal of 2^28 / 2^32 against another literal, n11 callee-only length,
#     n12 pattern binders swapped, n13 untracked if/match length, n14 val-pattern binders swapped  -> `mismatch FILE:LINE`
#     (n1 .. n3, n6 .. n8: exactly one diag line and no missingEntry.)  n15 a fresh-length array (Array.fill(n * 2, 0)) passed where length n is needed -> `mismatch`.
#     p1 .. p7 (p6 Array.fill with a non-name size, p7 a non-name expression as a length argument: fresh rigid, sound, no diag) -> no diag line, `lengthNotName=0`, mismatches=0.
#  2. the 3 length negatives of tests/s2/neg (array_field :6, array_grow_stale :7, bytes_len :9) with lib/prelude.srs first -> `mismatch FILE:LINE`.
#  3. `--types` of the 13 s3c files: mismatches=0 lengthNotName=0.
#  Armed: the same checks with every expected line shifted by 1 must all fail, and a forced failure line shows the script can fail.
. tests/s3/lib.sh
init T-l "$1"
D=tests/s3/types/len
S13="lib/prelude.srs s2/sym.srs s2/coll.srs s2/bmap.srs s3/lex.srs s3/parse.srs s3/ast.srs s3/parse2.srs s3/print.srs s3/names.srs s3/types.srs s3/emit.srs s3/main.srs"
num() { printf '%s\n' "$1" | sed -n "s/.* $2=\([0-9]*\).*/\1/p" | head -1; }

# chk FILE VERDICT LINE OFF: the output of s3c --types lib/prelude.srs FILE carries `VERDICT FILE:LINE+OFF` (mismatch | lengthNotName) or, for ok, no diag
chk() {
  local f=$1 v=$2 l=$3 off=$4 out
  # an ok program has no line to shift: under the arming shift it counts as a miss
  [ "$v" = ok ] && [ "$off" != 0 ] && return 1
  out=$(timeout 20 "$BIN" --types lib/prelude.srs "$f" 2>&1)
  if [ "$v" = ok ]; then
    [ "$(num "$out" mismatches)" = 0 ] && [ "$(num "$out" lengthNotName)" = 0 ] \
      && ! printf '%s\n' "$out" | grep -qE '^(mismatch|lengthNotName|missingEntry|annotate|nonexhaustive|untyped) ' && return 0
    return 1
  fi
  # a rejected length (n1 .. n3) gives ONE diag line, no missingEntry for its subnodes (n6 .. n8: the error length compares equal to every length, no follow-on mismatch)
  if [ "$v" = lengthNotName ]; then
    printf '%s\n' "$out" | grep -q '^missingEntry ' && return 1
    case "$f" in */n[1236-8]_*) [ "$(printf '%s\n' "$out" | grep -cE '^(mismatch|lengthNotName|missingEntry|annotate|nonexhaustive|untyped) ')" = 1 ] || return 1;; esac
  fi
  printf '%s\n' "$out" | grep -q "^$v $f:$((l + off)) " && return 0
  return 1
}

# run OFF: sets NP NF MISS over the planted programs and the 3 s2 negatives
run() {
  NP=0; NF=0; MISS=""
  for f in $D/*.srs; do
    first=$(head -1 "$f"); last=$(tail -1 "$f")
    case "$first" in
      *"error[lengthNotName]"*) v=lengthNotName;;
      *"error[mismatch]"*) v=mismatch;;
      *"expect: ok"*) v=ok;;
      *) v=?;;
    esac
    l=$(printf '%s\n' "$last" | sed -n 's/.*--> [^:]*:\([0-9]*\)$/\1/p')
    [ "$v" = ok ] && l=0
    if [ "$v" = "?" ] || [ -z "$l" ]; then NF=$((NF+1)); MISS="$MISS $(basename "$f")(bad header)"; continue; fi
    if chk "$f" "$v" "$l" "$1"; then NP=$((NP+1)); else NF=$((NF+1)); MISS="$MISS $(basename "$f")($v:$l)"; fi
  done
  for pair in array_field:6 array_grow_stale:7 bytes_len:9; do
    n=${pair%%:*}; l=${pair##*:}; f=tests/s2/neg/$n.srs
    if chk "$f" mismatch "$l" "$1"; then NP=$((NP+1)); else NF=$((NF+1)); MISS="$MISS $n($l)"; fi
  done
}
run 0
total=$((NP+NF))
echo "T-l planted + s2 negatives: pass=$NP of $total"
for m in $MISS; do echo "  miss $m"; done
[ "$NF" = 0 ] && [ "$total" -ge 22 ] || bad "pass=$NP of $total (want all, >= 22 programs)"

# 3. the 13 s3c files
timeout 60 "$BIN" --types $S13 > "$T/s3.txt" 2>&1; rc=$?
b=$(grep '^bodies:' "$T/s3.txt" | head -1); ln=$(grep '^lengths:' "$T/s3.txt" | head -1)
echo "s3c 13 files: exit=$rc mismatches=$(num "$b" mismatches) $(printf '%s' "$ln")"
[ "$rc" = 0 ] || bad "s3c own exit=$rc"
[ "$(num "$b" mismatches)" = 0 ] || bad "s3c own mismatches=$(num "$b" mismatches)"
[ "$(num "$ln" lengthNotName)" = 0 ] || bad "s3c own lengthNotName=$(num "$ln" lengthNotName)"
[ -n "$ln" ] || bad "no lengths: line"

# armed: shifted by one line, every program must miss
run 1 > /dev/null
echo "armed (expected lines +1): pass=$NP of $total"
[ "$NP" = 0 ] || bad "not armed: shifted lines still pass ($NP)"
# armed: an ok program fed to a negative check must fail, a negative fed to the ok check must fail
chk $D/p1_ok_lit.srs mismatch 2 0 && bad "armed: an ok program has a mismatch line"
chk $D/n1_compound.srs ok 0 0 && bad "armed: a negative passes the ok check"
# forced failure
WHY0="$WHY"; bad "forced"; [ "$WHY" != "$WHY0" ] || echo "forced failure line did not record"; WHY="$WHY0"
finish
