# Contributing to srs

Thanks for wanting to help. This file is the workflow: how to build srs from nothing, how to test a change, how to show it works, and what makes us say no to a pull request. The [README](README.md) explains the language.

If you want to change the language itself (syntax, a typing rule, a new kind of declaration), open an issue first and show the srs code you would like to write. Design is decided before code, and a pull request that settles a design question on its own will be sent back to an issue.

## Setup

```console
$ nix develop
```

The devshell has everything: `zig cc` (our C compiler), hyperfine and jq for the speed check, and the commands below. Its menu lists them. CI runs the same commands, so what passes here passes there.

| Command | What it does |
|---|---|
| `srs-build` | build the compiler from `bootstrap/s2c-seed.c` to `$B/srs` |
| `srs-run [LIB...] FILE.srs` | compile with the prelude and run |
| `srs-test` | the gate: bootstrap, fixpoint, every test |
| `seed-update` | after a compiler change: the new seed is the compiler's own C |
| `srs-bench` | the speed check against `bench/baseline.txt` |
| `bench-update` | save a faster run as the new baseline |
| `ci` | `fmt-check`, `lint` and `srs-test`, in the order CI runs them |

`$B` is the build dir, `${XDG_RUNTIME_DIR}/srs-build`. Nothing the tests write goes anywhere else: even the content store of a test run lives under `$B`.

## How srs builds itself

```console
$ zig cc -o $B/s2c0 bootstrap/s2c-seed.c rt/srs_rt.c         # the seed is plain C
$ $B/s2c0 lib/prelude.srs s2/*.srs s2c/main.srs > $B/s2c1.c   # s2c0 compiles the compiler
$ $B/s2c1 lib/prelude.srs s2/*.srs s2c/main.srs > $B/s2c2.c   # and s2c1 compiles it again
$ cmp $B/s2c1.c $B/s2c2.c && cmp $B/s2c1.c bootstrap/s2c-seed.c
```

The compiler is written in srs (`s2/*.srs`, with the driver in `s2c/main.srs`), and the seed is its own C output. The gate runs exactly these steps. Two things must hold: `s2c1.c` and `s2c2.c` are the same bytes (the fixpoint), and both equal the seed (the seed is fresh). The C runtime is `rt/srs_rt.c`, and the compiler binaries link static on Linux (musl).

So a change to `s2/*.srs` or `s2c/main.srs` is a three-step loop:

```console
$ srs-test        # fails with "FAIL s2c seed stale: seed-update"
$ seed-update     # cp $B/s2c1.c bootstrap/s2c-seed.c
$ srs-test        # green, now with the new seed
```

`s0/`, `s1/`, `bootstrap/seed.c` and `tests/s1/` are the first two compilers. They are history, kept as documentation: nothing builds or runs them, and a change to them is not accepted.

## Testing

```console
$ srs-test > $B/gate.log 2>&1; echo EXIT=$?
```

The gate takes about two minutes and runs its test loops in parallel. Every line is `ok ...` or `FAIL ...`, and it exits non-zero on any `FAIL`. Don't edit `s2/`, `s2c/`, `tests/`, `lib/` or `rt/` while it runs, because its result is then about files that no longer exist.

What it checks, besides the bootstrap above:

| Where | The check |
|---|---|
| `s2/*.srs` | the compiler stays functional: no `var`, no `while`, no assignment |
| `tests/s2/*.srs` | component tests of the compiler's parts, output equals `.out` |
| `tests/s2/prog/` | compile, run, output equals `.out` |
| `tests/s2/neg/` | rejected, with every `// expect:` line in the output |
| `tests/s2/eval/` | `s2c --eval` prints each `// eval: name value` line |
| `tests/s2/hash/` | `s2c --hash` keeps `same`, `differ` and `golden` digests |
| `tests/s2/mem/` | `s2c --mem` equals `.out`, and the compiler's own report has no failures |
| `tests/s2/cok/`, `cneg/` | the emitted C must build, or must be refused by the C compiler with the expected message |
| `tests/s2/frag/`, `fragbase/` | the emitted C stays in its fragment, and the counts never grow |
| `tests/s2/fmt/` | `s2c fmt` rewrites and `--check` exits 1, then 0 |
| the store | `--store-check` cold, warm, cut, flip and trail |
| `tests/s2/todo` | must be empty: a listed test that passes is a failure |
| every source | `s2c fmt --check` |

A test program gets one second of CPU. A test that needs more is a test that needs a smaller input. Tail calls are also run at `-O0`, because `-O1` hides a missing loop.

To try one program quickly, without the whole gate:

```console
$ L="lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/s2/prog/list.lib tests/s2/prog/file.lib"
$ $B/s2c1 $L x.srs > $B/x.c
$ zig cc -std=gnu11 -O1 -w -o $B/x $B/x.c rt/srs_rt.c && $B/x
```

A component test compiles with the compiler's own sources: `$B/s2c1 lib/prelude.srs s2/*.srs tests/s2/<name>.srs > $B/x.c`.

And to try a compiler change before you update the seed, build the new compiler with the current one, then run it on the tests you care about:

```console
$ $B/s2c1 lib/prelude.srs s2/*.srs s2c/main.srs > $B/n.c
$ zig cc -std=gnu11 -O1 -w -o $B/n $B/n.c rt/srs_rt.c
```

Read the real exit code with `cmd > log 2>&1; echo EXIT=$?`. A pipe into `tail` hides it.

## Writing a change

```scala
// expect: error[use-after-free]
def main(): I64 =
  handle r = Srs.Arena()
  val xs = build(3)
  r.free()
  sum(xs)
// expect: --> tests/s2/neg/use_after_free.srs:7
```

Write the tests first. A feature comes with a program in `tests/s2/prog/` and its `.out`, and with a program in `tests/s2/neg/` that must be rejected. The `// expect:` lines name the error code and the exact `-->` line, so the test fails when the compiler rejects the program for some other reason.

Then make the smallest change that turns them green. Keep a change small: one idea, about an hour of work. A bigger one is several pull requests.

A few rules that come from how the compiler is built:

* **Errors are data.** No phase calls `err()` or exits. Each one returns its errors, and only `main` in `s2c/main.srs` prints them. Every error is reported, not only the first.
* **A new error has a code, a title and a help line**, in the Rust shape, added in `s2c/main.srs`.
* **Types, not checks.** Make invalid data impossible to build: an enum with exactly the right cases, never a `Bool` flag, a `-1` or a magic number.
* **The type level always ends.** A step budget that runs out is a rejection, never "don't know".
* **Fast from the start.** A change lands with its fast algorithm (an index, incremental work) and a measurement, not with a promise to speed it up later.

<details>
<summary>Things in srs that bite</summary>

* The compiler compiles itself, so `s2/` can use only what s2c accepts. Try a new construct in a small program first.
* srs has no closures and no lambdas. Write goals, streams and rules as data (enums) with an interpreter. A function you pass around is a given of a trait named by a marker type (`tests/s2/prog/fold.srs`).
* srs has no string concatenation. Name things by their parts and let the printer write them. To get printed output as a string, use `Console.captureBegin()` and `Console.captureEnd()`.
* Patterns are flat. `case K.Con(n, Coll.Nil)` binds a variable named `Coll.Nil`; match the inner value in a second `match`. There is no bare variable pattern: write the case with its fields.
* A `match` can't be a call argument, and an `if` can't continue on the next line: bind it to a `val` first.
* Check mode does not reach the arms of a `match` in an unannotated `val`: annotate it.
* All files share one namespace. Use module names (`Coll.List`, `T.range`) and grep `s2/` before you name something new.
* `Foo.bar` is one name; members are written qualified (`def Coll.rev`, `case Coll.Nil`).
* A self tail call is a C loop only in tail position: the body, an `if` branch, a `match` arm, or the last statement of a block without `handle`.
* Lines are numbered across all input files; s2c maps a line back to its file for `-->`.
* There is no xor or shift on `I64`. Hashes use `%` with products below 2^63.
* Constructors allocate through `srs_alloc`, which bumps the Arena inline (`s2/emit.srs`, `Emit.allocFast`). A change to the chunk layout in `rt/srs_rt.c` must change it too.

</details>

## Showing it works

```console
$ srs-test > $B/gate.log 2>&1; echo EXIT=$?
EXIT=0
$ srs-bench > $B/bench.log 2>&1; echo EXIT=$?
EXIT=0
```

A pull request says what changed and shows these commands with their output. "Works" or "green" without the output means nothing to the reviewer.

**Mutants.** For each rule your change adds, break that rule in the code on purpose (one place, checked with `cmp` or a diff) and run the tests: at least one must fail, with the error you expect and not some other one. A mutant that survives means a test is missing. Add it, and run the mutant again.

**Refactors.** When a change should not change what the compiler does, save the C of every test before it and compare it byte for byte after. Add one mutant that must change the output, to prove the comparison can fail.

**Speed.** `srs-bench` runs after `srs-test`. It runs `$B/s2c1` on a frozen corpus (`bench/corpus/`): `corpus-self` compiles the frozen compiler, `corpus-tests` compiles every frozen program test. It compares wall time, instructions and peak memory with `bench/baseline.txt`, and fails when a run is slower by more than two combined standard deviations. `info-s2c-self` times the current source and never fails. Trust the instruction counts when the machine is busy.

For speed work, measure before you change anything: callgrind (`nix-shell -p valgrind`, built with `-O1 -g -fno-inline`, inclusive costs) on a fixed input, then a counter after. To find what one phase costs, build a small driver that runs only that phase and time it. When a change is faster, `bench-update` saves the new baseline. To refreeze the corpus, copy the new sources into `bench/corpus/`, run `bench-update` with the old compiler at `$B/s2c1`, then build the new one and run `srs-bench`.

## Keep these lists in sync

* A new `s2/*.srs` file goes in `TT.sources` in `tests/s2/types.srs` (the compiler type-checks itself there), and in `bench/corpus/` at the next refreeze.
* A new `lib/*.srs` goes in `S2LIBS` in `tests/run.sh` and `CLIBS` in `tests/bench.sh`.
* A change that lands gets a line in the [CHANGELOG](CHANGELOG.md): projects that build with srs read it to see what moving their pin brings.

## Commits

We use [jj](https://jj-vcs.github.io/jj/). The seed is about 3 MB, so jj needs a bigger snapshot limit:

```console
$ jj --config snapshot.max-new-file-size=4000000 commit -m "flow: a call checks its callee's exit facts"
```

A commit message starts with the part it touches (`flow:`, `emit:`, `datalog:`, `tests:`) and says what changed in plain words. It quotes nobody. A bug you find outside your change gets its own issue, not a fix in passing.

## What gets a pull request rejected

* The gate is not green, or the seed is stale.
* No test, or no negative test, or a `// expect:` line without the exact `-->` location.
* A mutant of the new rule survives.
* `srs-bench` is slower than the baseline, or a speed claim has no measurement.
* A skipped or disabled test, a suppressed warning, or a workaround around a bug instead of its cause.
* A test listed in `tests/s2/todo`, or one that needs more than one second.
* `var`, `while` or assignment in `s2/*.srs`, or a phase that exits instead of returning its errors.
* A new error without a code, a title and a help line.
* A sentinel value or a `Bool` where an enum would make the wrong state impossible.
* Any change to `s0/`, `s1/`, `bootstrap/seed.c` or `tests/s1/`.
* A language or design decision made in code, without an issue where it was agreed.
* Unformatted sources (`s2c fmt --check`), or a change much bigger than its one idea.
* Claims of "works", "faster" or "fixed" without the command and its output.
