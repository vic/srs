#!/bin/bash
# standing NAMES tests (NAMES-1): shadowing, arm scope, global-vs-local priority, no scope leak between decls.
# bash tests/s3/names/standing.sh <s3c> (from the repo root). Inputs: nd.srs nd2.srs leak.srs in this directory.
# dump line shape: path:line text kind target ; a Local target = bindline:text ut= tt=, a Global target = file:line:name
. tests/s3/lib.sh
init N-standing "$1"
D=tests/s3/names
chk() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$3] want [$2]"; bad "$1"; fi; }
at() { echo "$1" | awk -v l="$2" -v t="$3" '{split($1,a,":")} a[2]==l && $2==t {print $3 " " $4; exit}'; }
n1=$(timeout 20 "$BIN" --names-dump $D/nd.srs)
chk "nd.srs:6 x -> binder line 5"   "Local 5:x" "$(at "$n1" 6 x)"
chk "nd.srs:7 x -> binder line 6"   "Local 6:x" "$(at "$n1" 7 x)"
chk "nd.srs:10 q Unresolved (arm None binds nothing)" "Unresolved -" "$(at "$n1" 10 q)"
chk "nd.srs:9 q Local (arm Some binds q)" "Local 9:q" "$(at "$n1" 9 q)"
n2=$(timeout 20 "$BIN" --names-dump $D/nd2.srs)
chk "nd2.srs:4 x Local (not the global x)" "Local" "$(at "$n2" 4 x | cut -d' ' -f1)"
chk "nd2.srs:5 x Local (not the global x)" "Local" "$(at "$n2" 5 x | cut -d' ' -f1)"
chk "nd2.srs:4 x -> binder line 3"  "Local 3:x" "$(at "$n2" 4 x)"
chk "nd2.srs:5 x -> binder line 4"  "Local 4:x" "$(at "$n2" 5 x)"
# leak.srs: the param s of f (line 2) is gone at g (line 3): s() there is the global s of line 1
n3=$(timeout 20 "$BIN" --names-dump $D/leak.srs)
chk "leak.srs:2 s Local (the param)" "Local 2:s" "$(at "$n3" 2 s)"
chk "leak.srs:3 s Global (no leak from f)" "Global 0:1:s" "$(at "$n3" 3 s)"
s3=$(timeout 20 "$BIN" --names $D/leak.srs)
chk "leak.srs --names: unresolved=0" "1" "$(echo "$s3" | grep -c ' unresolved=0 ')"
chk "leak.srs --names: leaks=0" "1" "$(echo "$s3" | grep -c ' leaks=0')"
# the arming: chk (run in a subshell, so its bad is lost) must print FAIL for a wrong expectation
armed=$(chk "armed" "Local 99:x" "$(at "$n1" 6 x)" | grep -c '^FAIL armed')
echo "armed (wrong binder line): reported=$armed"
[ "$armed" = 1 ] || bad "not armed: chk accepted a wrong value"
finish
