# srs

[![Sponsor](https://img.shields.io/badge/sponsor-vic-ea4aaa?logo=githubsponsors)](https://github.com/sponsors/vic)

srs is a small language with Scala 3 syntax that compiles to portable C. It has no garbage collector. Instead, the compiler checks at compile time who owns memory, who may write it, and in what order a resource can be used (open, read, close).

The compiler, `s2c`, is written in srs (`./s2`, driver in `./s2c`) and compiles itself: its own C output (`bootstrap/s2c-seed.c`) builds it again, byte for byte. That is how we know a change did not break it.

If you only have five minutes, read the first three sections of the tour. The rest goes from there to the parts that make srs different.

## Try it

```console
$ nix develop
$ srs-run hello.srs
24
```

`hello.srs` is plain code. Nothing in it is special yet:

```scala
enum Shape:
  case Circle(r: I64)
  case Rect(w: I64, h: I64)

def area(s: Shape): I64 = s match
  case Circle(r) => 3 * r * r
  case Rect(w, h) => w * h

def main(): I64 =
  handle io = Srs.Console()
  handle r = Srs.Arena()
  Console.printI64(area(Rect(3, 4)) + area(Circle(2)))
  Console.print("\n")
  0
```

The two `handle` lines are the first idea to get used to. `Console` is printing, `Arena` is memory. `main` says which handlers it provides, and the compiler checks that every other function only asks for things `main` gave it. We come back to this in [effects](#4-effects-main-decides-what-the-program-may-do).

## The tour

Each step links the tests that run it. Tests in `tests/s2/prog/` compile, run, and must print their `.out`. Tests in `tests/s2/neg/` must be rejected, with the error code and the line named in the file.

### 1. Enums and `match`

A `match` must cover every case. Add a case to an enum and the compiler points at every match that forgot it:

```console
error[not-exhaustive]: match is not exhaustive, missing case 'Cons'
```

Tests: [`neg/nonexhaustive`](tests/s2/neg/nonexhaustive.srs). Pattern binders are plain variables, and `val C(a, b) = e` takes apart a one-case enum ([`prog/val_pattern`](tests/s2/prog/val_pattern.srs)).

### 2. No loops needed: `val`, recursion, tail calls

The compiler itself uses only `val` and recursion. A self tail call becomes a C loop, so deep recursion costs no stack ([`prog/tailcall`](tests/s2/prog/tailcall.srs), [`prog/stack_deep`](tests/s2/prog/stack_deep.srs)). `var` and `while` exist for code that wants them ([`prog/scope_var`](tests/s2/prog/scope_var.srs)).

### 3. Names with dots, and generics

`Foo.bar` is one name, the dot is part of it. That is how modules work for now, and two modules can both define `Term` or `step`:

```scala
enum Kanren.Term:
  case Kanren.TVar(n: I64)
  case Kanren.TInt(v: I64)

def Kanren.step(t: Kanren.Term): I64 = t match
  case Kanren.TVar(n) => n
  case Kanren.TInt(v) => v + 100
```

Type parameters go in `[A: Type]`. Generic code is specialized into plain C, one struct per instance:

```scala
enum Gen.Opt [A: Type]:
  case Gen.None
  case Gen.Some(v: A)

def Gen.get [A: Type] (o: Gen.Opt[A], d: A): A = o match
  case Gen.None => d
  case Gen.Some(v) => v
```

Tests: [`prog/modules`](tests/s2/prog/modules.srs), [`prog/generic_enum`](tests/s2/prog/generic_enum.srs), [`prog/generic`](tests/s2/prog/generic.srs).

### 4. Effects: `main` decides what the program may do

A function that prints just calls `Console.print(s)`. You never write that it needs `Console`: the compiler works it out from the body. `main` has to handle every effect the program uses (`handle io = Srs.Console()`), and if it does not, you get `error[unhandled-effect]`. Pure things, like `Str.len(s)`, ask for nothing.

```scala
def greet(s: Str): Unit =
  Console.print(s)
  Console.printI64(Str.len(s))
  Console.printChar(10)
```

The `Srs.*` handlers are the only place that touches the C runtime (`rt_*`), anywhere else it is `error[rt-outside-srs]`.

Tests: [`prog/eff_console`](tests/s2/prog/eff_console.srs), [`prog/eff_inner`](tests/s2/prog/eff_inner.srs), [`prog/eff_shadow`](tests/s2/prog/eff_shadow.srs), [`neg/os_rt_outside`](tests/s2/neg/os_rt_outside.srs).

### 5. Traits and givens

Contextual evidence is written in `{}` and found for you, with the same rules as Scala 3: local evidence first, then the most specific given, and an ambiguous choice is an error.

```scala
trait Show [A: Type]:
  def show(x: A): I64

given Show[I64]:
  def show(x: I64): I64 = x + 1

given [A: Type] {s: Show[A]} Show[Box[A]]:
  def show(x: Box[A]): I64 = x match
    case Box(v) => 100 + s.show(v)

def print [A: Type] {s: Show[A]} (x: A): Unit =
  Console.printI64(s.show(x))
```

At a call, `f[T](x)` gives type arguments and `f{a}(x)` picks the evidence by hand. Searches that run too long are rejected, never guessed.

Tests: [`prog/givens`](tests/s2/prog/givens.srs), [`prog/given_rank`](tests/s2/prog/given_rank.srs), [`prog/given_local`](tests/s2/prog/given_local.srs), [`neg/given_ambig`](tests/s2/neg/given_ambig.srs), [`neg/given_fuel`](tests/s2/neg/given_fuel.srs).

### 6. Memory without a GC: regions

Every value lives in a region. `Srs.Arena` is a bump allocator in srs itself, over `mmap`. `Srs.Heap` lets you free by hand. You rarely write `{r: Region}`: the compiler finds the region for you. When two are open, you name one: `build{a}(3)`.

The compiler rejects a value used after its region ended:

```scala
def main(): I64 =
  handle r = Srs.Arena()
  val xs = build(3)
  r.free()
  sum(xs)
```

```console
error[use-after-free]: use of a value after its region ended: 'r'
  --> tests/s2/neg/use_after_free.srs:7
    |
  7 |   sum(xs)
    |
    = help: use it before the region ends, or allocate it in a longer region
```

A result can't escape the region it lives in either (`error[region-escape]`), and a region is never stored in a struct or returned. A game loop can open a small `Srs.Arena` per tick so memory stays flat.

Tests: [`prog/region_ok`](tests/s2/prog/region_ok.srs), [`prog/arena_tick`](tests/s2/prog/arena_tick.srs) (2000 ticks, peak memory stays flat), [`prog/arena_reuse`](tests/s2/prog/arena_reuse.srs), [`neg/use_after_free`](tests/s2/neg/use_after_free.srs), [`neg/escape`](tests/s2/neg/escape.srs), [`neg/tparam_escape`](tests/s2/neg/tparam_escape.srs), [`neg/var_loop`](tests/s2/neg/var_loop.srs). The region of a type is written glued to it, `T<r>` ([`prog/caret_glued`](tests/s2/prog/caret_glued.srs)).

### 7. Capabilities: a resource with an order

A `capability` is a state machine. It says which states exist, where it starts, where it must stop, and which calls move it:

```scala
capability Door:
  state Shut, Open1, Open2, Gone
  start Shut
  stop Gone
  transition knock Shut -> Open1, Open1 -> Open2
  def knock <s knock t> (): I64 <t>
  transition leave Open1 -> Gone, Open2 -> Gone
  def leave <s leave t> (): Unit <t>

handler HDoor for Door:
  def knock(): I64 = 3
  def leave(): Unit = ()
```

Calling `leave` on a shut door is `error[op-not-allowed]`. Forgetting to end it is `error[capability-not-ended]`. Regions are capabilities too, so a double free is the same kind of error:

```scala
def main(): I64 =
  handle r = Srs.Arena()
  r.free()
  r.free()
  0
```

Capabilities are erased at run time: they cost nothing in the C, and they can't be stored in a value (`error[capability-erased]`).

Tests: [`prog/capability`](tests/s2/prog/capability.srs), [`prog/caps`](tests/s2/prog/caps.srs), [`prog/cap_seq`](tests/s2/prog/cap_seq.srs), [`neg/double_free`](tests/s2/neg/double_free.srs), [`neg/missing_close`](tests/s2/neg/missing_close.srs), [`neg/call_freed`](tests/s2/neg/call_freed.srs), [`neg/erased_arg`](tests/s2/neg/erased_arg.srs).

### 8. Facts and rules about states

The `<>` groups talk about states. Before the arguments they say what a function needs, after the result what it leaves behind. They can also hold Datalog rules, so you can say "two knocks" and let the checker work out the states:

```scala
capability Door:
  ...
  rule def twoKnocks(s, s3) = next(s, knock, s2), next(s2, knock, s3)

def knockTwice {d: Door} <d: s, twoKnocks(s, s3)> (): I64 <d: s3> =
  val a = d.knock()
  a + d.knock()
```

The binder groups, in order: `[A: Type]` types, `{s: Show[A]}` evidence and capabilities, `<...>` facts, `(x: A)` values.

Tests: [`prog/capability`](tests/s2/prog/capability.srs), [`prog/rules`](tests/s2/prog/rules.srs), [`prog/facts`](tests/s2/prog/facts.srs), [`prog/facts_vars`](tests/s2/prog/facts_vars.srs), [`neg/tf_stale`](tests/s2/neg/tf_stale.srs), [`neg/rule_reach`](tests/s2/neg/rule_reach.srs), [`neg/rule_safety`](tests/s2/neg/rule_safety.srs).

### 9. Handlers that keep state, and handlers that resume

A handler can carry state. The state is a `Cell`, and it lives in the region of the `handle`:

```scala
capability Tick:
  def tick(): I64

handler Cnt for Tick:
  def init(): Cell[I64] = Cell.new(0)
  def tick(self: Cell[I64]): I64 =
    Cell.put(self, Cell.get(self) + 1)
    Cell.get(self)
```

A handler can also resume the rest of the program, more than once. This one runs a program that picks twice, and collects every outcome:

```scala
capability NonDet:
  def choose(): Bool

handler All [A: Type] for NonDet:
  def done(x: A): Bag[A] = Leaf(x)
  def choose(k): Bag[A] = Two(resume k(true), resume k(false))

def pick(): I64 =
  val c = NonDet.choose()
  if c then 1 else 2
```

Run on `x * 10 + y` with two picks, it prints `11 12 21 22`. There is no closure in srs: the compiler cuts the rest of the block into a continuation that is plain data.

Tests: [`prog/hstate_count`](tests/s2/prog/hstate_count.srs), [`prog/hstate_self`](tests/s2/prog/hstate_self.srs), [`prog/ms_pick`](tests/s2/prog/ms_pick.srs), [`prog/ms_sum`](tests/s2/prog/ms_sum.srs), [`prog/ms_if`](tests/s2/prog/ms_if.srs), [`prog/ms_state_trip`](tests/s2/prog/ms_state_trip.srs), [`neg/ms_resume_not_k`](tests/s2/neg/ms_resume_not_k.srs), [`tests/c/multishot`](tests/c/multishot) (the C prototypes this started from).

### 10. Arrays, bytes and numbers

`Array[A](n)` carries its length as a value. You index it only where an `if` proves the index is in range, so the C is a plain `p[i]` with no check. `xs.at(j)` is the safe way: it gives you `Ok` or `Out`, never a crash.

```scala
def Ar.sum(n: I64, xs: Array[I64](n), i: I64, acc: I64): I64 =
  if i >= 0 && i < n then Ar.sum(n, xs, i + 1, acc + xs(i)) else acc
```

There are also `Cell[A]`, the sized types `U8`, `I32`, `F64` (a C double, with `F64.fmt` and `F64.parse`), 64-bit word operations, and BLAKE3.

Tests: [`prog/array`](tests/s2/prog/array.srs), [`prog/array_put`](tests/s2/prog/array_put.srs), [`prog/array_grow`](tests/s2/prog/array_grow.srs), [`prog/cell`](tests/s2/prog/cell.srs), [`prog/bytes`](tests/s2/prog/bytes.srs), [`prog/i32`](tests/s2/prog/i32.srs), [`prog/f64_prims`](tests/s2/prog/f64_prims.srs), [`prog/f64_fmt`](tests/s2/prog/f64_fmt.srs), [`neg/array_escape`](tests/s2/neg/array_escape.srs).

### 11. The outside world, and C

Files, environment, clock, network and processes are capabilities too: `Files`, `Env`, `Clock`, `Net`, `Process`. A failure is a value (`Os.NotFound`, `Os.Denied`, ...) and never aborts the program. Only `main` may handle them, so a library can't reach the world behind your back (`error[ambient-world]`).

C comes in through `extern "libc"`: a function with its real header behind it, a struct read from the header, a constant as a value. A call to one is only legal inside a `Srs.*` handler, so the unsafe part stays in a small place.

```scala
extern "libc" val O_RDONLY: I32

def flags(): I64 = I64.ofI32(O_RDONLY) + I64.ofI32(MADV_HUGEPAGE)
```

Tests: [`prog/os_files`](tests/s2/prog/os_files.srs), [`prog/os_env`](tests/s2/prog/os_env.srs), [`prog/os_clock`](tests/s2/prog/os_clock.srs), [`prog/os_net`](tests/s2/prog/os_net.srs), [`prog/os_proc`](tests/s2/prog/os_proc.srs), [`prog/libc_val`](tests/s2/prog/libc_val.srs), [`prog/cstruct_decl`](tests/s2/prog/cstruct_decl.srs), [`prog/cstr_type`](tests/s2/prog/cstr_type.srs), [`neg/ambient_env`](tests/s2/neg/ambient_env.srs), [`neg/ambient_files`](tests/s2/neg/ambient_files.srs), [`neg/erased_extern`](tests/s2/neg/erased_extern.srs).

### 12. Types that compute, and evidence on types

A type can ask for evidence, mention a state, or be computed by a pure function:

```scala
type SortedBox [A: Type] {o: Ord[A]} = Box[A]
type OpenFile {f: File} <at(f, Opened)> = Ptr

type Bits (n: I64) = n match
  case 8 => Bool
  case _ => I64
```

The type level is pure and always ends: if the step budget runs out, that is a rejection, never "don't know". A top-level `val x: T = e` is computed at compile time, and `s2c --eval` prints each one.

Tests: [`prog/type_values`](tests/s2/prog/type_values.srs), [`prog/type_facts`](tests/s2/prog/type_facts.srs), [`prog/type_evidence`](tests/s2/prog/type_evidence.srs), [`prog/typelambda`](tests/s2/prog/typelambda.srs), [`eval/basic`](tests/s2/eval/basic.srs), [`eval/neg_fuel`](tests/s2/eval/neg_fuel.srs), [`neg/tl_fuel`](tests/s2/neg/tl_fuel.srs), [`neg/tval_fuel`](tests/s2/neg/tval_fuel.srs), [`neg/cval_impure`](tests/s2/neg/cval_impure.srs).

### 13. Names are hashes

`s2c --hash` names a function by the hash of its syntax tree, not by what you called it. Rename the arguments and the hash stays. `s2c --store-check` writes declarations into a content-addressed store (`SRS_STORE`, default `$HOME/.srs/store`), the way Nix and Unison do. A store entry is written through a typestate protocol, so a write that is not committed does not compile.

Tests: [`hash/basic`](tests/s2/hash/basic.srs), [`hash/valpat`](tests/s2/hash/valpat.srs), [`hash/golden`](tests/s2/hash/golden.srs).

### 14. What the compiler knows about your memory

The default C is already optimized: only the defs that `main` and the handlers reach are emitted, a case with one box field is that pointer, and a def that runs once and makes many boxes runs in a scratch Arena that is freed after the result is copied out. `--no-mem-optimization` gives the plain C.

`s2c --mem` prints what the analysis found, as one JSON object: each region and what fills it, each allocation site (its bytes, whether it dies in its def or escapes), each variable's moves, and where a box can be rebuilt in place (`--mem-reuse`). The analysis is a Datalog program, and the gate audits the report of the compiler on itself.

```console
$ s2c --mem lib/prelude.srs tests/s2/mem/once.srs
{"regions":[{"id":0,"def":"main","var":"r","handler":"Srs.Arena", ...
```

Tests: [`tests/s2/mem/`](tests/s2/mem) (`once`, `many`, `death`, `frees`, `moves`, `reuse`, ...), [`prog/scratch`](tests/s2/prog/scratch.srs), [`prog/reuse_run`](tests/s2/prog/reuse_run.srs), [`prog/tagless`](tests/s2/prog/tagless.srs).

### 15. Logic engines, in srs

miniKanren (unification, disequality `=/=`, finite domains) and Datalog (semi-naive, indexed columns, stratified negation, a proof for every derived fact) are libraries written in srs. The compiler checks itself with the Datalog one.

Tests: [`prog/kanren_search`](tests/s2/prog/kanren_search.srs), [`prog/kanren_neq`](tests/s2/prog/kanren_neq.srs), [`prog/kanren_fd`](tests/s2/prog/kanren_fd.srs), [`prog/datalog`](tests/s2/prog/datalog.srs), [`prog/turnstile`](tests/s2/prog/turnstile.srs) (a type checker as a relation), [`dprov`](tests/s2/dprov.srs) (the proof of each fact), [`datalog`](tests/s2/datalog.srs), [`kfd`](tests/s2/kfd.srs).

### 16. Contracts

`requires`, `ensures`, `invariant`, `decreases` and `proof by induction` parse, check, and erase in the C. The Lean 4 output (`--lean`) waits until the core stops moving.

Tests: [`prog/contracts`](tests/s2/prog/contracts.srs).

## Errors

Errors look like Rust's: a code, the file and line, the source line, what was expected and found when types differ, and a help line. A phase returns its errors as data and `main` prints every one of them, not only the first. The compiler never exits in the middle of a check.

## Working on srs

```console
$ srs-test            # the gate: seed -> s2c -> s2c again (same C), then every test
$ srs-bench           # speed: fails if slower than bench/baseline.txt
$ s2c fmt [--check] FILES   # srs to srs, 120 columns, drops decls nothing reaches
```

The gate also checks that the seed is not stale, that s2 stays functional (`val` only), and that every file is formatted. A test program gets one second of CPU. `tests/s2/todo` must stay empty.

Every change that lands is in the [CHANGELOG](CHANGELOG.md), newest first. A project that builds with srs pins a bookmark and reads it to see what moving the pin brings. Contributor rules are in [AGENTS.md](AGENTS.md).

`s0` and `s1` (the first compilers) are history. They stay in the tree and nothing builds or runs them.

## Coming next

* **s3**: relational macros written as patterns and evaluated at compile time, type-directed encoders and decoders, and synthesis from a signature.
* **Lean 4**: proofs of the kernel rules, once the core is stable.
* The rough edges of s2 come first. They are tracked and fixed before s3.

## Why these papers

<details>
<summary>Foundations and literature</summary>

* **Syntax & type system**
  * [Scala 3](https://docs.scala-lang.org/scala3/): surface syntax, givens, traits, indentation.
  * [Scoped Capabilities for Polymorphic Effects](https://arxiv.org/abs/2207.03402) (*Odersky et al., 2022*): capture checking.
  * [A Gentle Introduction to Second-Class Values](https://www.cs.purdue.edu/homes/rompf/papers/osvald-oopsla16.pdf) (*Osvald et al., OOPSLA 2016*): capabilities that do not escape.
* **Memory & typestate**
  * [Region-Based Memory Management](http://web.cs.ucla.edu/~palsberg/tba/papers/tofte-talpin-iandc97.pdf) (*Tofte & Talpin, 1997*): regions and their inference.
  * [Region-Based Memory Management in Cyclone](https://www.cs.umd.edu/projects/cyclone/papers/cyclone-regions.pdf) (*Grossman et al., 2002*): explicit regions, safe manual free.
  * [Typestate](https://doi.org/10.1109/TSE.1986.6312929) (*Strom & Yemini, 1986*): state-dependent checking.
  * [Enforcing High-Level Protocols in Low-Level Software](https://doi.org/10.1145/378795.378811) (*DeLine & Fahndrich, 2001*): Vault, key-tracked states.
  * [Modular Typestate Verification of Aliased Objects](http://www.cs.cmu.edu/~kbierhof/papers/typestate-verification.pdf) (*Bierhoff & Aldrich, 2007*): access permissions.
  * [fx-rs](https://github.com/denful/fx-rs): effect handlers.
* **Logic engines & errors**
  * [microKanren](http://webyrd.net/scheme-2013/papers/HemannMuKanren2013.pdf) (*Hemann & Friedman, 2013*): the relational core.
  * [Flix](https://flix.dev) (*Madsen et al.*): Datalog inside a functional language.
  * [Better Together: Unification-based Equality Saturation in Egglog](https://arxiv.org/abs/2304.04332) (*Zhang et al., 2023*): round-stamped semi-naive Datalog.
  * [Provenancing Datalog Execution in Souffle](https://arxiv.org/abs/1907.05045) (*Zhao, Subotic & Scholz, 2019*): proofs of derived facts.
  * [Total Type Error Localization and Recovery with Holes](https://doi.org/10.1145/3632910) (*Zhao et al., POPL 2024*): report every error.
  * [Type Systems as Macros](https://www2.ccs.neu.edu/racket/pubs/popl17-ckg.pdf) (*Chang, Knauth & Greenman, POPL 2017*): type checking as relational expansion.
* **Hashing, proofs & runtimes**
  * [Unison](https://www.unison-lang.org): content-addressed code.
  * [The Lean 4 Theorem Prover and Programming Language](https://lean-lang.org/papers/lean4.pdf) (*de Moura & Ullrich, 2021*).
  * [yen](https://github.com/vic/yen): Datalog in Nix.
  * [dnx](https://github.com/denful/dnx): a Nix runtime on [persistent delta interaction nets](https://github.com/vic/persistent-delta-interaction-nets/blob/main/pidnets.pdf), the reason srs exists.

</details>

## Support

srs is made and maintained by **vic**. Issues, pull requests and [sponsors](https://github.com/sponsors/vic) are welcome.
