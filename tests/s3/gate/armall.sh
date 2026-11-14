#!/bin/bash
# armall.sh [DIR]: for every row of tests/s3/gate/subset.sh, a scratch copy of DIR (default s3, from the repo root) with exactly one
# violation must FAIL that row (and subset.sh must exit 1). Takes no s3c. Last line `PASS armall` | `FAIL armall (...)`.
D=${1:-s3}
[ -d "$D" ] || { echo "FAIL armall (no dir $D)"; exit 1; }
G=$(mktemp -d "${TMPDIR:-/tmp}/s3t.XXXXXX") || { echo "FAIL armall (mktemp)"; exit 1; }
trap 'rm -rf "$G"' EXIT
t=0; ok=0
arm() { # name, row-label, the line appended to zz.srs; DUPMAIN / HANDLEOUT: a second handle in main.srs / a handle in print.srs
  rm -rf "$G/arm"; mkdir -p "$G/arm"; cp "$D"/*.srs "$G/arm/"
  case "$3" in
    DUPMAIN) printf '  handle io2 = Srs.Console()\n' >> "$G/arm/main.srs";;
    HANDLEOUT) printf '  handle q = Srs.Mut()\n' >> "$G/arm/print.srs";;
    *) printf '%s\n' "$3" >> "$G/arm/zz.srs";;
  esac
  out=$(bash tests/s3/gate/subset.sh "$G/arm" 2>&1); code=$?
  t=$((t+1))
  if echo "$out" | grep -E "^$2 +[1-9][0-9]* +FAIL" > /dev/null && [ $code = 1 ]; then ok=$((ok+1)); echo "armed ok   : $1 -> row '$2' FAIL"; else echo "NOT ARMED  : $1 ($2)"; echo "$out" | grep -E "$2" | head -2; fi
}
arm trait 'trait' 'trait Show:'
arm given 'given' 'given Show[I64]:'
arm evidence 'evidence call f{x}\(' 'def f(x: I64): I64 = show{x}(x)'
arm type 'type decl' 'type T = I64'
arm val 'top-level val' 'val k = 1'
arm multi 'multi handler shots' 'handler Foo for P multi:'
arm resume 'resume >1 in one op body' '  def choose(k): I64 = resume k(true) + resume k(false)'
arm twohandlers 'non-Region cap >1 handler \(for\)' $'handler P for Tally:\nhandler Q for Tally:\n  handle p = P()\n  handle q = Q()'
arm facts '<facts> after params' 'def g(x: I64) <p>: I64 = x'
arm noresult 'def without result type' 'def h(x: I64) = x'
arm handleout 'handle outside entry files' HANDLEOUT
arm dup 'capability with >1 handle site' DUPMAIN
echo "armed rows: $ok / $t"
# the clean copy must pass
bash tests/s3/gate/subset.sh "$D" > /dev/null; clean=$?
echo "clean $D: subset exit=$clean"
if [ $ok = $t ] && [ $clean = 0 ]; then echo "PASS armall"; exit 0; fi
echo "FAIL armall (armed $ok/$t, clean exit $clean)"; exit 1
