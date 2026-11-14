#!/usr/bin/env bash
# run.sh <engine-binary>  (from the repo root). Oracle of S1b-3a step 1: the index-proof rules as data on the Datalog engine
# (s3/bounds.srs, binary = s3/dl.srs + s3/bounds.srs + s3/dlmain.srs) equal Souffle (proof2.dl) site by site on the three fact sets.
#   `<bin> --prf-dump FACTS` prints one line per unproved site (def, site, file, line, name, kind, cause) = Souffle's firstun.csv.
# DATA (committed, tests/s3/bounds/data): the fact dumps facts_{s3,y1,progs}.txt of the idx walker (S1b-0) and the Souffle answers
# souffle_{s3,y1,progs}.csv = the unproved sites of proof.dl (the rule TEXT, beside the hand-written numeric plan of s3/bounds.srs:
# the plan is data written by hand until the rule-text -> plan compiler exists: this oracle is the proof that plan and text agree).
# Regenerate the answers: souffle on tests/s3/bounds/proof.dl with the facts split per relation (see the S1b-0 notes). Override with
# $S1B_DATA. Controls: tests/s3/bounds/ctl1.facts (1 proved, 3 unproved), ctl_kill.facts (0 proved, 1 unproved: the killed rule),
# ctl_eq.facts (2 proved, 1 unproved: assign at the site does not kill, literal index equal to the literal length is not proved).
# Output dir $OUT (default $TMPDIR or /tmp). Last line PASS bounds | FAIL bounds (why).
bin=${1:?usage: run.sh <engine-binary>}
F=${S1B_DATA:-tests/s3/bounds/data}
S=$F
O=${OUT:-${TMPDIR:-/tmp}/bounds-out}
mkdir -p "$O"
why=""
bad() { why="${why:+$why; }$1"; }
[ -x "$bin" ] || { echo "FAIL bounds (no engine binary '$bin')"; exit 1; }
# set name, expected sites proved unproved, causes (compound array-not-local no-upper no-lower)
chk() {
  n=$1; exp=$2
  [ -f "$F/facts_$n.txt" ] && [ -f "$S/souffle_$n.csv" ] || { bad "$n: missing reference data in $F"; return; }
  timeout 120 "$bin" --prf-dump "$F/facts_$n.txt" > "$O/$n.out" 2> "$O/$n.err"; rc=$?
  [ $rc = 0 ] || bad "$n exit $rc"
  grep -v '^#' "$O/$n.out" | sort > "$O/$n.unp"
  sort "$S/souffle_$n.csv" > "$O/$n.souffle"
  d=$(diff "$O/$n.unp" "$O/$n.souffle" | grep -c '^[<>]')
  got=$(grep '^# sites' "$O/$n.out" | sed 's/# //; s/ defs=.*//'; grep '^# compound' "$O/$n.out" | sed 's/# //')
  echo "$n: $(echo $got) | diff lines vs Souffle: $d"
  [ "$d" = 0 ] || bad "$n differs from Souffle ($d lines)"
  [ "$(echo $got)" = "$exp" ] || bad "$n counts '$(echo $got)' expected '$exp'"
}
chk s3 "sites=336 proved=234 unproved=102 compound-index=19 array-not-local=2 no-upper-guard=70 no-lower-bound=11"
chk y1 "sites=119 proved=7 unproved=112 compound-index=28 array-not-local=2 no-upper-guard=71 no-lower-bound=11"
chk progs "sites=83 proved=27 unproved=56 compound-index=5 array-not-local=4 no-upper-guard=39 no-lower-bound=8"
ctl() {
  timeout 120 "$bin" --prf-dump "tests/s3/bounds/$1.facts" > "$O/$1.out" 2>&1
  g=$(grep '^# sites' "$O/$1.out" | sed 's/.*proved=\([0-9]*\) unproved=\([0-9]*\).*/\1\/\2/')
  echo "control $1: proved/unproved $g (expect $2)"
  [ "$g" = "$2" ] || bad "control $1 $g expected $2"
}
ctl ctl1 1/3
ctl ctl_kill 0/1
# ctl_eq: an assign AT the site position does not kill (ap < pos), and a literal index equal to the literal length is not below it
# (v < n / 2). Souffle on this file: 2 proved, 1 unproved (no-upper-guard). Kills the Lt -> Le mutants.
ctl ctl_eq 2/1
if [ -z "$why" ]; then echo "PASS bounds"; exit 0; fi
echo "FAIL bounds ($why)"; exit 1
