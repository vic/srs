#!/bin/bash
# E-c (EMIT-1 mutants): bash tests/s3/emit/ec.sh <s3c> (from the repo root). Two emitter mutants, each built from a COPY of s3/emit.srs
# (the mutated copy is written under $HOME/.cache, the source is never edited), then tests/s3/emit/eb.sh-style runs of EC_PROGS progs
# (default: the first 40 of progs.txt) must show >= 1 failure per mutant:
#   m1 swap two case tags: a constructor with tag 0 builds tag 1 and the reverse (the patterns are unchanged)
#   m2 field index + 1: the field i of a constructor / pattern is written f(i+1)
# The unmutated build is the control: it must pass the same progs (EC_PROGS) first. Needs SEED (default $HOME/.cache/srs3/seed/srs).
. tests/s3/lib.sh
init E-c "$1"
SEED=${SEED:-$HOME/.cache/srs3/seed/srs}
S2LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s2/prog/list.lib tests/s2/prog/file.lib"
SRCS="lib/prelude.srs s2/sym.srs s2/coll.srs s2/bmap.srs s3/lex.srs s3/parse.srs s3/ast.srs s3/parse2.srs s3/print.srs s3/names.srs s3/types.srs"
W=$(mktemp -d "$HOME/.cache/srs3/ec.XXXXXX"); trap 'rm -rf "$T" "$W"' EXIT
N=${EC_PROGS:-17}
head -"$N" tests/s3/emit/progs.txt > "$W/progs.txt"
# fails <s3c binary> -> number of the progs of $W/progs.txt that do not build and match their .out
fails() {
  local bin=$1 f=0 n src out
  while read -r n; do
    src="tests/s2/prog/$n.srs"
    if ! timeout 20 "$bin" --emit $S2LIBS "$src" > "$W/p.c" 2> /dev/null; then f=$((f + 1)); continue; fi
    if ! timeout 120 zig cc -std=gnu11 -O0 -fsanitize=address,undefined -w -o "$W/p.bin" "$W/p.c" rt/srs_rt.c $(sed -n 's|^// c: ||p' "$src") 2> /dev/null; then f=$((f + 1)); continue; fi
    out=$(env $(sed -n 's|^// env: ||p' "$src") timeout 20 "$W/p.bin" 2> /dev/null) || { f=$((f + 1)); continue; }
    [ "$out" = "$(cat "tests/s2/prog/$n.out")" ] || f=$((f + 1))
  done < "$W/progs.txt"
  echo "$f"
}
build() { # name copy-of-emit.srs
  timeout 120 "$SEED" $SRCS "$2" s3/main.srs > "$W/$1.c" 2> "$W/$1.err" || return 1
  timeout 120 zig cc -std=gnu11 -O1 -w -static -target x86_64-linux-musl -o "$W/$1" "$W/$1.c" rt/srs_rt.c || return 1
}
c0=$(fails "$BIN"); echo "control (unmutated): $c0 failing of $N"
[ "$c0" = 0 ] || bad "control fails $c0 of $N progs: the mutant counts mean nothing"
# m1: the tag a constructor writes (Em.ctor: `Console.printI64(Em.ax(e, n) - 1)` after `.t_ = `)
awk '{ if ($0 ~ /^    Console.print\("\.t_ = "\)$/) { print; getline; if ($0 ~ /Console.printI64\(Em.ax\(e, n\) - 1\)/) { print "    Console.printI64(if Em.ax(e, n) == 1 then 1 else if Em.ax(e, n) == 2 then 0 else Em.ax(e, n) - 1)"; next } } print }' s3/emit.srs > "$W/m1.srs"
# m2: field i of a constructor is written f(i+1): the line `Console.printI64(i)` right after `.f` in Em.fields
awk '{ print; if ($0 ~ /^    Console.print\("\.f"\)$/ && !done) { getline; if ($0 ~ /Console.printI64\(i\)/) { print "    Console.printI64(i + 1)"; done = 1; next } else print } }' s3/emit.srs > "$W/m2.srs"
for m in m1 m2; do
  if cmp -s s3/emit.srs "$W/$m.srs"; then bad "$m: the mutation matched nothing"; continue; fi
  if build $m "$W/$m.srs"; then
    f=$(fails "$W/$m"); echo "$m: $f failing of $N"
    [ "$f" -ge 1 ] || bad "$m survived (0 failing of $N)"
  else echo "$m: the mutant does not build ($(head -c 200 "$W/$m.err"))"; bad "$m does not build"; fi
done
finish
