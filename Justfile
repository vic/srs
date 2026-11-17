# srs actions. Image work (load, submit, store, cycle, build) goes through the s4-cc socket of a running kernel (`just serve`);
# these recipes cover the shell side: build the kernel from the seed, run its CLI modes, compile and run emitted C.

cc := env("CC", "gcc")
out := "build"
sock := env("SRS_SOCK", "/run/user/1000/cc-socks/s4-k0.sock")

# list the recipes
default:
    @just --list

# the kernel from the seed with nix (result/bin/srs)
build:
    nix build

# the kernel from the seed with the local C compiler (build/srs), only when the seed or the runtime is newer
bootstrap:
    #!/usr/bin/env bash
    set -eu
    mkdir -p {{out}}
    if [ {{out}}/srs -nt bootstrap/srs_seed.c ] && [ {{out}}/srs -nt bootstrap/srs_rt.c ]; then exit 0; fi
    {{cc}} -std=gnu11 -O1 -w -o {{out}}/srs bootstrap/srs_seed.c bootstrap/srs_rt.c -lm

# fixpoint (CI): the kernel loads ./srs through its whole gate and emits C byte-identical to the seed it was built from
fixpoint: bootstrap
    {{out}}/srs --build srs {{out}}/fixpoint.c
    cmp {{out}}/fixpoint.c bootstrap/srs_seed.c

# start the s4-cc server on the socket; then send it `load` with the absolute path of ./srs
serve: bootstrap
    {{out}}/srs {{sock}}

# gate check of FILE over the library BASE: exit 0 = rejected, 1 = accepted
neg base file: bootstrap
    {{out}}/srs --neg {{base}} {{file}}; echo "exit=$?"

# gate check of FILE over BASE with the diagnostics written to DIAGS
negt base file diags: bootstrap
    {{out}}/srs --negt {{base}} {{file}} {{diags}}; cat {{diags}}

# the C of FILE over BASE (exit 1 = written)
emit base file outc: bootstrap
    rm -f {{outc}}
    {{out}}/srs --emit {{base}} {{file}} {{outc}}; test -s {{outc}}

# emit FILE over BASE, compile it with the runtime and run it
run base file: (emit base file out / "prog.c")
    {{cc}} -std=gnu11 -O0 -w -o {{out}}/prog {{out}}/prog.c bootstrap/srs_rt.c -lm
    {{out}}/prog

# run FILE over BASE under valgrind: no memory error allowed; prints the heap alloc count (Srs.Heap blocks are malloc'd, so a
# Heap use-after-free or a Heap allocation routed to the wrong region shows here; Arena pages are invisible to valgrind)
memcheck base file: (emit base file out / "prog.c")
    {{cc}} -std=gnu11 -O0 -g -w -o {{out}}/prog {{out}}/prog.c bootstrap/srs_rt.c -lm
    valgrind -q --error-exitcode=9 --leak-check=no {{out}}/prog
    valgrind --leak-check=no {{out}}/prog 2>&1 >/dev/null | grep 'total heap usage'

# the in-image Tests of BASE as a C runner OUTC with its report REPORT
tests base outc report: bootstrap
    {{out}}/srs --tests {{base}} {{outc}} {{report}}

# remove local build outputs
clean:
    rm -rf {{out}} result
