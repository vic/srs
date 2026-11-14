#!/bin/bash
# subset.sh [DIR]: the s3 subset gate over DIR/*.srs (default: s3, run from the repo root). Read-only. Takes no s3c.
# Counts that must be 0: trait, given, evidence calls, type, top-level val, multi shots, <facts> after params, defs w/o result type.
# `handle ` sites are counted and must all be in an entry file (main.srs, dlmain.srs), one per capability per entry file.
# The last line is `PASS subset` or `FAIL subset (...)`; exit 0 | 1. tests/s3/gate/armall.sh arms every row.
D=${1:-s3}
[ -d "$D" ] || { echo "FAIL subset (no dir $D)"; exit 1; }
cnt() { cat "$D"/*.srs | grep -c -E "$1"; }
fail=0; WHY=""
row() { printf '%-34s %6s  %s\n' "$1" "$2" "$3"; }
chk() { n=$(cnt "$2"); if [ "$n" = 0 ]; then row "$1" "$n" ok; else row "$1" "$n" FAIL; fail=1; WHY="${WHY:+$WHY, }$1"; fi; }
echo "dir: $D ($(ls "$D"/*.srs | wc -l) files, $(cat "$D"/*.srs | wc -l) lines)"
chk 'trait'               '^[[:space:]]*trait '
chk 'given'               '^[[:space:]]*given '
chk 'evidence call f{x}(' '[a-z][A-Za-z0-9_.]*\{[a-z][a-zA-Z0-9_, ]*\}\('
chk 'type decl'           '^[[:space:]]*type '
chk 'top-level val'       '^val '
chk 'multi handler shots' '(^|[^A-Za-z0-9_])multi([^A-Za-z0-9_]|$)'
# region caps are glued `)<g>` (no space); facts after params have a space: `) <...>`
chk '<facts> after params' '^def [^=]*\)[[:space:]]+<'
n=$(cat "$D"/*.srs | grep -E '^def ' | grep -c -v -E '\)[[:space:]]*:[[:space:]]*[A-Za-z]')
if [ "$n" = 0 ]; then row 'def without result type' "$n" ok; else row 'def without result type' "$n" "FAIL (line-based; multi-line headers count too)"; fail=1; WHY="${WHY:+$WHY, }def without result type"; fi
# a handle SITE is a statement: `handle` first on its line (a string literal "handle " is not a site)
# law: each capability has ONE handle, in main. Entry files (main.srs, dlmain.srs) are separate programs.
# capability name = the handler constructor of `handle x = Srs.Name(...)`. FAIL: a handle outside an entry file, or a
# capability with > 1 handle site in one entry file. Table: capability | file | count.
echo "handle sites (capability | file | count):"
tab=$(grep -H -E '^[[:space:]]*handle ' "$D"/*.srs | sed -E 's|^.*/([^/:]+):[[:space:]]*handle [A-Za-z0-9_]+ = ([A-Za-z0-9_.]+).*|\2 \1|' | sort | uniq -c | awk '{print $2 " | " $3 " | " $1}')
echo "$tab" | sed 's/^/  /'
hout=$(echo "$tab" | awk -F' [|] ' '$2!="main.srs" && $2!="dlmain.srs" && $1!=""' | grep -c .)
hdup=$(echo "$tab" | awk -F' [|] ' '$3+0>1' | grep -c .)
if [ "$hout" = 0 ]; then row 'handle outside entry files' 0 ok; else row 'handle outside entry files' "$hout" FAIL; fail=1; WHY="${WHY:+$WHY, }handle outside entry files"; fi
if [ "$hdup" = 0 ]; then row 'capability with >1 handle site' 0 ok; else row 'capability with >1 handle site' "$hdup" FAIL; fail=1; WHY="${WHY:+$WHY, }capability with >1 handle site"; fi
if [ $fail = 0 ]; then echo "PASS subset"; exit 0; fi
echo "FAIL subset ($WHY)"; exit 1
