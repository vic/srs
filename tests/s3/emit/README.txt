tests/s3/emit: the 81 in-subset tests/s2/prog programs for the s3 emit oracles.

Named reasons for a program outside the 82 of PROG-0 (not in progs.txt):
  multi-shot: resume called twice in an op body   (ms_state_trip: `resume k(true) + resume k(false)`; ruled out of the s3 subset by the lead)
One-shot resume (EMIT-1 rule, lead): a handler op body with exactly one `resume k(v)` in TAIL position emits `return v` in the static handler fn
(the continuation param k is no C param). A resume in non-tail position is the named emit Diag `unsupportedResume`, counted in the emit
summary line (the emit exits 1): never guessed C.

progs.txt lists them (names without .srs), sorted by source size. rt.sha256 pins rt/srs_rt.c.

How a prog is built (the rule of tests/run.sh, S2LIBS on line 59 and t_prog on lines 68-73): the s2 gate compiles each prog together with
the library set, then the prog:

  S2LIBS="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s2/prog/list.lib tests/s2/prog/file.lib"
  <compiler> $S2LIBS tests/s2/prog/NAME.srs

s3c takes the .lib files as ordinary source files (it reads every path it is given), so the typing oracle is

  s3c --types $S2LIBS tests/s2/prog/NAME.srs

Two kinds of lines in a prog are NOT for the compiler:
  // c: ARGS     extra cc arguments for the C compile of the emitted file
  // env: A=1 B= variables set for the RUN of the compiled program (an empty value is set empty)
Typing ignores both. The expected stdout of a run is tests/s2/prog/NAME.out.

Emit oracles (EMIT-1): ea.sh = E-a (s3c --emit, then tcc -c and zig cc -std=c11 -Werror: 0 diagnostics), eb.sh = E-b (zig cc -O0
-fsanitize=address,undefined + rt/srs_rt.c, run with the // env: variables, exit 0 and stdout == NAME.out). Deviation from the brief: the
E-a zig check is `zig cc -std=c11 -Werror -Wno-unused-command-line-argument -c -o FILE`, NOT `-fsyntax-only`: in this zig, -fsyntax-only (also
with -o /dev/null) fails with "failed to rename 'tmp/..-p.o' into '.../p.o': FileNotFound", and `zig clang` finds no stdint.h. -c runs the
same clang frontend, so the diagnostics are the same. Both scripts take longer than 120 s: run.sh gives them 900 s.

Typed oracle (tests/s3/types/ty.sh): 82 progs typed with this command; a prog that does not type is listed with its first diag.
