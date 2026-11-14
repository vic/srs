# s3

s3 is the third srs compiler. It does not port s2. It starts again and keeps what s2 taught us. s2 works, but some of its costs could not be removed from inside it. Its collections copy paths on every update, and they took 735 of 997 MB of typed allocation on our yardstick. It freed memory by copying live data out at run time, which cost 140% more instructions. Its Datalog was interpreted and stored about 833 bytes per row, where Souffle stores about 25. Its strings did not know their length, and `Str.at` returned -1 when out of range. s3 is designed so that these faults cannot be written, and so that the compiler knows every fact about the program it compiles.

## Where it is

s3c is written in the subset of the language that s2 and s3 share, and s2c compiles it. At commit 61db4d4 s3c compiles itself: the s3c that s2c builds and the s3c that it builds from its own C emit the same C for its 13 source files, byte for byte (943,501 bytes). One changed character in the source changes the output; ASLR and the working directory do not. A standing test, `tests/s3/emit/fixpoint.sh`, checks this on every run.

Be clear about what that means. s3c runs NO checks yet: it parses, resolves names, types every def and emits C, but none of the Datalog checks that s3 promises exist in it today. s2c stays the acceptance gate for every s3c source commit. s3 does not replace s2 yet.

The landed parts are the lexer, the parser, a flat AST with U32 ids, name resolution, the type namespace, per-def type checking with a typed AST, and a C emitter that prints explicit C11 types that tcc and zig both accept.

On Y1 (31 files, 23,961 lines) at commit 61db4d4, the self-built s3c uses 610,662,878 instructions, 123,572 KB peak memory and 24,190 minor page faults to emit C. That is about half the memory of s2c on the same input. 78 of the s2 test programs are inside the s3 subset; 77 of them build with s3c and print their expected output. The one that does not, `cstruct_new`, is rejected cleanly because calls on extern struct fields are not typed yet (bead srs3-0gc). Two programs outside the subset are accepted today and run wrong (srs3-1ny, srs3-4kj); the subset law becomes a Datalog check with negative tests (srs3-v2m).

## What s3 is built to promise

These are design laws, not features you can use today.

Every check is a Datalog rule over typed facts, never a hand-written check function. Relations are typed records, so a wrong column does not compile. Analyses run per def, not as one whole-program solve.

Values are owned by default. Unique data changes in place, and sharing is a declared form. Every allocation has a static destination region that the caller passes, so nothing is copied out or forwarded at run time.

Sizes are part of types: `Str(n)`, `Array[A](n)`, `Fin(n)`. An index needs `Fin` evidence, made only by a guard, a loop bound or a checked `.get` that returns `Option`. An unproved index is a compile error, so there are no hidden bound checks and no sentinels. There is no null; `Never` is the uninhabited type.

A def can return named outcomes, and the caller must handle each one by name. Datalog analyses stop because the program's facts are finite, never because a fuel counter runs out. Output never depends on file or thread order: parallel work must give the same bytes as serial work.

## How we build it

We change code only after we have measured the change. Each step starts with a small experiment that sizes the gain, then sets a bar, adds an armed control, and kills a mutant before it lands. Nothing lands that is slower, uses more memory or leaves an unchecked path. Speed bars read the self-built s3c, never the one that s2c builds.

Run every s3 oracle from the repo root:

```
$ bash tests/s3/run.sh <s3c-binary>
```

Each oracle prints `PASS name` or `FAIL name (why)`, then a total. At 61db4d4 it prints 26 pass and 2 fail; both fails are `cstruct_new`.

## Next

The first Datalog check is the move check: which use of a value is its last, over def-local facts. On an unlanded change it already agrees with classic liveness on all 25,406 moves in Y1 with 54 times fewer rows, but it costs 1,066 M instructions over the front end, against a bar of 61 M. We are measuring where that cost goes before we change the engine. After the move check: flat unique collections replace the s2 collections that s3c still imports, then regions in the emitted C, then `Str(n)` and `Fin` in s3c's own source, then parallel per-def work.

## Credits

s3 learns from these projects and copies none of them: Souffle, the bar for our Datalog speed and memory; Tofte and Talpin's region inference (1997), for destination regions; Polonius, for ownership as Datalog; koru, for outcomes that the caller must handle and obligations kept in types; zed, for analyses without fuel, scaling oracles and bit-identical parallel results; and Go, the bar for compile speed.
