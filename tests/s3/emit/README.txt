tests/s3/emit: the 82 in-subset tests/s2/prog programs for the s3 emit oracles.

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

Typed oracle (tests/s3/types/ty.sh): 82 progs typed with this command; a prog that does not type is listed with its first diag.
