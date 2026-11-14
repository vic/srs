#!/bin/bash
# T-x (TYPES-1b, named Diags). bash tests/s3/types/tx.sh <s3c> (run from the repo root)
#  1. Y1: `s3c --types` reports diags: nonexhaustive=0 (every match / val pattern of the s2 sources covers its enum) and annotate=0.
#  2. tests/s2/neg: every file expecting error[not-exhaustive] must give a `nonexhaustive FILE:LINE` Diag at the expected line, every file
#     expecting error[cannot-infer] an `annotate FILE:LINE` Diag at its line (the libs are the ones of tests/run.sh S2LIBS). Q12.
#  3. tests/s3/types/want_neg.srs: exactly one annotate Diag, at line 7 (line 10 is solved by its sibling arm).
#  armed: with every expected line shifted by one, no file may pass. mutants (measured by hand, each needs a rebuild): Tp.exhaustive made `()`:
#     the not-exhaustive files fail (2 of 2); Tp.unsolved made `()`: the cannot-infer files and want_neg fail.
#  The final line carries the ratio of the negatives that were found at their line.
. tests/s3/lib.sh
init T-x "$1"
LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s2/prog/list.lib tests/s2/prog/file.lib"
num() { printf '%s\n' "$1" | sed -n "s/.* $2=\([0-9]*\).*/\1/p" | head -1; }

# 1. Y1
d=$(timeout 60 "$BIN" --types $Y1 | grep '^diags:' | head -1)
echo "Y1: $d"
[ "$(num "$d" nonexhaustive)" = 0 ] || bad "Y1 nonexhaustive=$(num "$d" nonexhaustive) (want 0)"
[ "$(num "$d" annotate)" = 0 ] || bad "Y1 annotate=$(num "$d" annotate) (want 0)"

# 2. tests/s2/neg: CODE KIND OFF -> NP NF MISS
run() {
  NP=0; NF=0; MISS=""
  for f in $(grep -l "expect: error\[$1\]" tests/s2/neg/*.srs); do
    exp=$(awk -v code="[$1]" -v off="$3" '/expect: error\[/{u=(index($0, code) > 0)} /expect: -->/{ if(u){n=split($0,a,":"); print a[n]+off} }' "$f" | sort -un | tr '\n' ' ')
    got=$(timeout 20 "$BIN" --types $LIBS "$f" | awk -v f="$f" -v k="$2" '$1==k && index($2,f":")==1{split($2,a,":"); print a[2]}' | sort -un | tr '\n' ' ')
    ok=1
    for e in $exp; do case " $got " in *" $e "*) ;; *) ok=0;; esac; done
    [ -n "$exp" ] || ok=0
    if [ $ok = 1 ]; then NP=$((NP+1)); else NF=$((NF+1)); MISS="$MISS $(basename $f)(exp=[$exp]got=[$got])"; fi
  done
}
run not-exhaustive nonexhaustive 0; ep=$NP; ef=$NF; em=$MISS
run cannot-infer annotate 0; cp=$NP; cf=$NF; cm=$MISS
echo "not-exhaustive negatives: found=$ep of $((ep+ef))"
for m in $em; do echo "  miss $m"; done
echo "cannot-infer negatives: found=$cp of $((cp+cf))"
for m in $cm; do echo "  miss $m"; done
[ "$ef" = 0 ] && [ "$ep" -ge 2 ] || bad "not-exhaustive $ep of $((ep+ef)) (want all, >= 2)"
[ "$cf" = 0 ] && [ "$cp" -ge 4 ] || bad "cannot-infer $cp of $((cp+cf)) (want all, >= 4)"

# 3. want_neg: one annotate at line 6
w=$(timeout 20 "$BIN" --types lib/prelude.srs tests/s3/types/want_neg.srs)
wa=$(num "$(printf '%s\n' "$w" | grep '^diags:')" annotate)
wl=$(printf '%s\n' "$w" | awk '$1=="annotate"{split($2,a,":"); print a[2]}' | tr '\n' ' ')
echo "want_neg: annotate=$wa at lines [$wl] (want 1 at [7 ])"
[ "$wa" = 1 ] && [ "$wl" = "7 " ] || bad "want_neg annotate=$wa lines=[$wl]"

# armed: expected lines shifted by one
run not-exhaustive nonexhaustive 1; sp=$NP
run cannot-infer annotate 1; sp=$((sp+NP))
echo "armed (expected lines +1): pass=$sp (want 0)"
[ "$sp" = 0 ] || bad "not armed: shifted lines still pass ($sp)"
NAME="T-x not-exhaustive=$ep/$((ep+ef)) cannot-infer=$cp/$((cp+cf)) Y1-nonexhaustive=$(num "$d" nonexhaustive) Y1-annotate=$(num "$d" annotate)"
finish
