#!/bin/bash
# T-y (TYPES-1c, the typed AST store). bash tests/s3/types/ty.sh <s3c> (run from the repo root)
#  The typer leaves, per AST node, everything it decided in side tables (ty = the ground type id, ce = the callee / case / handler / op symbol,
#  ax = the mono site or the case tag), so the emitter does no unification and no name lookup. A node that needs an entry and has none is the
#  named Diag `missingEntry`.
#  1. Y1 (31 files): `s3c --types` exits 0 with untypednodes=0 (so no k90: every builtin call is typed), mismatches=0, nonground=0 (no node
#     with an absent type or a type var), logover=0, missingEntry=0 (ty / callee / tag-site / literal kind).
#  2. `s3c --types-kinds Y1`: per node kind nodes vs ty entries; every REQUIRED kind (expression, pattern, call, ctor, literal, binder) has
#     records == nodes: required-gaps=0. The kinds that need no entry (types, decls, layout, clauses) are listed, with required=NO.
#  3. the 78 in-subset progs (tests/s3/emit/progs.txt), each typed with the S2LIBS set + the prog (tests/s3/emit/README.txt): `progs typed N/78`
#     (exit 0, untypednodes=0, mismatches=0, missingEntry=0, required-gaps=0), the others listed with their first diag. bar: >= 70.
#  4. spot oracle: `s3c --types-dump-nodes Y1` (path:line #id kind type [rhs=#id]): every val / var binding of Y1 whose source line has an explicit
#     annotation (`val x: T =`) has the type of its rhs node equal to its binder type (the annotation); 30 random ones are shown.
#  mutants (measured by hand on a copy, rebuilt; numbers in the report): Array.fill untyped again -> step 3 fails (k90 > 0 on the progs);
#     case tags not recorded -> missingEntry > 0 and steps 1 and 2 fail.
. tests/s3/lib.sh
init T-y "$1"
num() { printf '%s\n' "$1" | sed -n "s/.* $2=\([0-9]*\).*/\1/p" | head -1; }
S2LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s2/prog/list.lib tests/s2/prog/file.lib"

# 1. Y1
timeout 60 "$BIN" --types $Y1 > "$T/y1.txt"; rc=$?
bl=$(grep '^bodies:' "$T/y1.txt" | head -1); tl=$(grep '^tynodes:' "$T/y1.txt" | head -1); dl=$(grep '^diags:' "$T/y1.txt" | head -1)
echo "Y1: exit=$rc $(printf '%s' "$bl" | cut -c1-70)"; echo "Y1: $tl"; echo "Y1: $dl"
[ "$rc" = 0 ] || bad "Y1 exit=$rc"
[ "$(num "$bl" untypednodes)" = 0 ] || bad "Y1 untypednodes=$(num "$bl" untypednodes)"
printf '%s\n' "$bl" | grep -q 'k90=' && bad "Y1 has k90 (an untyped builtin call)"
[ "$(num "$bl" mismatches)" = 0 ] || bad "Y1 mismatches=$(num "$bl" mismatches)"
[ "$(num "$tl" nonground)" = 0 ] && [ "$(num "$tl" logover)" = 0 ] || bad "Y1 $tl"
[ "$(num "$dl" missingEntry)" = 0 ] || bad "Y1 missingEntry=$(num "$dl" missingEntry)"
[ "$(num "$tl" records)" -gt 50000 ] || bad "Y1 records=$(num "$tl" records) (want > 50000)"

# 2. per kind
timeout 60 "$BIN" --types-kinds $Y1 | grep -E '^(kind |required-gaps)' > "$T/kinds.txt"
cat "$T/kinds.txt"
[ "$(grep -c '^kind ' "$T/kinds.txt")" -ge 40 ] || bad "kinds table too short"
[ "$(grep '^required-gaps' "$T/kinds.txt")" = "required-gaps=0" ] || bad "required kinds with records != nodes: $(grep '^required-gaps' "$T/kinds.txt")"
[ "$(grep -c 'required=YES' "$T/kinds.txt")" -ge 25 ] || bad "too few required kinds"

# 3. the progs
ok=0; tot=0; fails=""; k90n=0
while read -r n; do
  tot=$((tot + 1))
  timeout 20 "$BIN" --types $S2LIBS "tests/s2/prog/$n.srs" > "$T/p.txt" 2>&1; prc=$?
  pb=$(grep '^bodies:' "$T/p.txt" | head -1)
  if printf '%s\n' "$pb" | grep -q 'k90='; then k90n=$((k90n + 1)); fi
  gaps=$(timeout 20 "$BIN" --types-kinds $S2LIBS "tests/s2/prog/$n.srs" | grep '^required-gaps')
  if [ "$prc" = 0 ] && [ "$(num "$pb" untypednodes)" = 0 ] && [ "$(num "$pb" mismatches)" = 0 ] && [ "$gaps" = "required-gaps=0" ] && [ -n "$pb" ]; then ok=$((ok + 1))
  else fails="$fails$n: exit=$prc $gaps $(grep -m1 -E '^(mismatch|untyped|annotate|nonexhaustive|missingEntry) ' "$T/p.txt" | cut -c1-90)"$'\n'; fi
done < tests/s3/emit/progs.txt
echo "progs typed $ok/$tot"
printf '%s' "$fails"
[ "$tot" = 78 ] || bad "progs.txt has $tot entries (want 78)"
[ "$k90n" = 0 ] || bad "$k90n progs have an untyped builtin call (k90)"
[ "$ok" -ge 70 ] || bad "progs typed $ok/78 (bar 70)"

# 4. spot oracle: annotated val / var bindings
timeout 60 "$BIN" --types-dump-nodes $Y1 | grep -v '^missing' | grep -E '^[^ ]+:[0-9]+ #[0-9]+ [0-9]+ ' > "$T/dn.txt"
grep -nE '^ *(val|var) [A-Za-z0-9_]+ *: ' $Y1 | cut -d: -f1,2 > "$T/ann.txt"
# join: a val / var row (kind 23 / 24) carries its binder type and rhs=#id; the rhs type is the row of that node id of the same file
awk 'NR==FNR{ann[$1]=1; next}
  { split($1, pl, ":"); id=$2; sub(/^#/, "", id); kind=$3; t=$0; sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", t);
    rhs=""; if ((kind==23 || kind==24) && match(t, / rhs=#[0-9]+$/)) { rhs=substr(t, RSTART+6); t=substr(t, 1, RSTART-1) }
    if (kind==23 || kind==24) { if ((pl[1] ":" pl[2]) in ann) { n++; bp[n]=pl[1]; bl[n]=pl[2]; br[n]=rhs; bt[n]=t } }
    else rt[pl[1] SUBSEP id]=t }
  END{ for (i=1;i<=n;i++) { r=rt[bp[i] SUBSEP br[i]]; print bp[i] ":" bl[i], (r==bt[i] ? "eq" : "NE"), bt[i], "|", r } }' "$T/ann.txt" "$T/dn.txt" > "$T/spot.txt"
na=$(wc -l < "$T/spot.txt"); ne=$(grep -c ' NE ' "$T/spot.txt")
echo "annotated val/var bindings: $na, rhs type != annotation: $ne"
shuf -n 30 --random-source=<(yes) "$T/spot.txt" | head -30
[ "$na" -ge 100 ] || bad "only $na annotated bindings found"
[ "$ne" = 0 ] || bad "$ne annotated bindings with rhs type != annotation: $(grep -m3 ' NE ' "$T/spot.txt" | tr '\n' ';')"
NAME="T-y Y1 missingEntry=0 required-gaps=0 progs=$ok/$tot spot=$((na - ne))/$na equal"
finish
