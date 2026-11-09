# srs: Scala 3 Syntax Meets Zero-GC C

Welcome to **srs**—a small, modern systems programming language designed to give you the clean expression of Scala 3 with the bare-metal performance and predictable memory footprint of C. 

The compiler, s2c, is self-hosting: it is written in srs (`./s2` and `./s2c`), and its own C output (`bootstrap/s2c-seed.c`) builds it again, byte for byte. Rather than relying on a garbage collector, srs verifies memory lifetimes, mutable state, and custom resource transitions entirely at compile time using algebraic flow effects and typestate protocols. The compiled output is clean, portable C with zero runtime bookkeeping overhead.

---

## Why SRS?

If you love high-level functional programming but need tight control over performance and resources, srs was built for you:

* **Scala 3 Design, C Execution**: Enjoy `enum`, `match`, `trait`, `given`, and clean whitespace-based indentation, compiling directly to any C target.
* **Algebraic Effects for Memory & Resources**: Inspired by structural Algebraic Effects with Handlers [fx-rs kernel](https://github.com/denful/fx-rs/blob/main/crates/fx/src/kernel/fx.rs), Tofte-Talpin region inference, Cyclone, and capture checking. Memory and state management are modeled as effects with handlers.
* **Content-Addressed Execution**: Following Unison and Nix derivations, functions and values are named by the cryptographic hash of their abstract syntax tree (AST) and effect requirements. Code can be cached in a global Nix-style store, shared across workspace agents without re-compilation, and hot-patched live.
* **Formal Verification**: Compiles to both C for production binaries and Lean 4 for proving kernel invariants.
* **Real-World Mission**: Built to power [`dnx`](https://github.com/denful/dnx), a next-generation Nix runtime executing on [persistent delta interaction nets](https://github.com/vic/persistent-delta-interaction-nets/blob/main/pidnets.pdf).

---

## Where We Are

s2 is the compiler. It is purely functional (`val` and recursion, no `var` or `while`) and built on a Datalog and miniKanren substrate. It reports every error, not only the first.

* **Self-hosting**: `bootstrap/s2c-seed.c` builds s2c. s2c compiles its own source to the same C, byte for byte.
* **Checks**: names, protocol facts and rules, type-level computation, types with givens, purity, exhaustive matches, typestate protocols, and region lifetimes. Each runs as a phase whose errors are data.
* **Flags**: `--eval` runs pure defs at compile time, `--hash` prints content hashes, and `--store-check` writes and reads the content-addressed store.
* **Errors** have the shape of Rust's: `error[code]`, then the file and line, the source line, the expected and found types, and a help line.

s1, the first compiler (imperative, written in srs), and s0, its Zig bootstrap, are still in the tree and are being removed. Lean generation (`--lean`) waits until the core is stable. The known rough edges of s2 are tracked before s3.

The s2 libraries live in `s2/`: persistent collections, miniKanren with disequality and finite domains, and Datalog with stratified negation. The checker phases also live there, and the driver lives in `s2c/`.

---

## Quick Start: Try It in 30 Seconds

```console
$ nix develop
$ srs-run hello.srs
24
```

Here is a quick look at `hello.srs`:

```scala
enum Shape:
  case Circle(r: I64)
  case Rect(w: I64, h: I64)

def area(s: Shape): I64 = s match
  case Circle(r) => 3 * r * r
  case Rect(w, h) => w * h

def main(): I64 =
  handle r = Arena()
  rt_print_i64(area(Rect(3, 4)) + area(Circle(2)))
  rt_print("\n")
  0
```

The line `handle r = Arena()` opens a new memory region. All allocations made inside are managed within this arena.

---

## Language Essentials

### 1. Exhaustive Pattern Matching
Pattern matching is a first-class expression in srs. Matches must be exhaustive; if you add an enum variant, the compiler flags missing handlers immediately:

```scala
enum Light:
  case Red
  case Yellow
  case Green

def wait(l: Light): I64 = l match
  case Red => 30
  case Yellow => 5
// Error: match is not exhaustive, missing case 'Green'
```

Because matches return values, they can serve as loop conditions (e.g., `while c match case Nil => false case Cons(_, _) => true do ...`).

**Tests:** [`tests/s2/neg/nonexhaustive.srs`](./tests/s2/neg/nonexhaustive.srs) rejects a match that misses a case.

### 2. Generics & Parametric Type Aliases
Type parameters are written inside square brackets `[A: Type]`. Generic code is fully monomorphized into C, delivering maximum runtime performance at the cost of compilation time and binary footprint.

```scala
enum Opt [A: Type]:
  case None
  case Some(v: A)

enum Pair [A: Type] [B: Type]:
  case Pair(a: A, b: B)

def get [A: Type] (o: Opt[A], d: A): A = o match
  case None => d
  case Some(v) => v

type Id [A: Type] = A
type Num = I64
type Maybe [A: Type] = Opt[Id[A]]

val m: Maybe[Num] = Some(1)
```

Type inference automatically determines generic arguments from call parameters or return annotations (e.g., `val n: Opt[I64] = None`).

**Tests:** [`tests/s2/prog/generic_enum.srs`](./tests/s2/prog/generic_enum.srs) (generic enums, one C struct per instance), [`tests/s2/prog/typelambda.srs`](./tests/s2/prog/typelambda.srs) (type aliases and match types).

### 3. Contextual Traits & Givens
Contextual evidence (like `Show[A]` instances) is declared with `given` and accepted inside curly braces `{}`.

```scala
trait Show [A: Type]:
  def show(x: A): I64

given Show[I64]:
  def show(x: I64): I64 = x

given [A: Type] {s: Show[A]} Show[Box[A]]:
  def show(x: Box[A]): I64 = x match
    case Box(v) => 100 + s.show(v)

def print [A: Type] {s: Show[A]} (x: A): Unit =
  rt_print_i64(s.show(x))
  rt_print("\n")
```

Calling `print(Box(41))` automatically resolves and links the requisite given instances. Resolution rules match Scala 3: local scope beats global givens, specific types beat general givens, ambiguous instances fail compilation, and recursive given searches are guarded by a fuel threshold.

**Tests:** [`tests/s2/prog/givens.srs`](./tests/s2/prog/givens.srs) (given clauses with evidence), [`tests/s2/prog/given_rank.srs`](./tests/s2/prog/given_rank.srs) (specificity ranking as in Scala 3), [`tests/s2/neg/given_ambig.srs`](./tests/s2/neg/given_ambig.srs) (ambiguous givens rejected), [`tests/s2/neg/given_fuel.srs`](./tests/s2/neg/given_fuel.srs) (search out of fuel rejected).

---

## Safe Memory & Resource Management

### 1. GC-Free Memory Regions
In srs, data lifetime is bound to a region capability `{r: Region}` passed as evidence. You can specify precise region annotations on types using `^<r>`:

```scala
def build {r: Region} (n: I64): List =
  if n == 0 then Nil else Cons(n, build(n - 1))

val q: Opt[I64]^<r> = Some(5)
```

Regions can be freed explicitly. The compiler enforces strict lifetime safety: access after region deallocation or escaping references are rejected at compile time.

```scala
def main(): I64 =
  handle h = Heap()
  val xs = build(3)
  h.free()
  sum(xs) // Error: use of value after its region ended: 'h'
```

Regions act as second-class capabilities—they cannot be stored in structs, returned from functions, or duplicated in a single call. When multiple regions exist in scope, you specify the target region explicitly (`build{a}(3)`). Mutable variables (`var`) track region state movements across loops and control flow branches conservatively.

**Tests:** [`tests/s2/prog/region_ok.srs`](./tests/s2/prog/region_ok.srs) (manual early free, then no use), [`tests/s2/neg/use_after_free.srs`](./tests/s2/neg/use_after_free.srs) (use after region end rejected), [`tests/s2/neg/tparam_escape.srs`](./tests/s2/neg/tparam_escape.srs) (a callee's result keeps the argument's region), [`tests/s2/neg/var_loop.srs`](./tests/s2/neg/var_loop.srs) (loop fixpoint over region state).

### 2. Typestate Protocols
Protocols model state machines for resources like files, locks, database transactions, or memory allocators. A protocol defines states, an initial state, terminal states, and valid operations:

```scala
protocol Door:
  state Shut, Open, Gone
  start Shut
  end Gone
  op knock(): I64 : Shut -> Open
  op leave(): Unit : Open -> Gone

handler WoodDoor for Door:
  def init(): Ptr = rt_arena_new()
  def knock(self: Ptr): I64 = 3
  def leave(self: Ptr): Unit = rt_arena_free(self)
```

The compiler enforces protocol ordering rules: calling `d.leave()` while in `Shut` state yields an error, as does failing to reach an `end` state before exiting scope.

Because memory regions are themselves protocols (`Region` protocol with handlers like `Arena`, `Heap`, or custom `Bump` allocators), double-frees and post-free allocations are caught as protocol state errors.

**Tests:** [`tests/s2/prog/rules.srs`](./tests/s2/prog/rules.srs) (a `Door` protocol that runs), [`tests/s2/neg/double_free.srs`](./tests/s2/neg/double_free.srs), [`tests/s2/neg/missing_close.srs`](./tests/s2/neg/missing_close.srs), [`tests/s2/neg/call_freed.srs`](./tests/s2/neg/call_freed.srs) (protocol state violations rejected).

---

## Signature Telescopes & Advanced Types

### 1. Telescope Signatures
Function signatures organize requirements left-to-right inside dedicated bracket pairs:

| Bracket | Purpose | Example |
| :--- | :--- | :--- |
| `[ A: Type ]` | Type Parameters | `[A: Type]` |
| `{ s: Show[A] }` | Contextual Evidence & Capabilities | `{r: Region}`, `{s: Show[A]}` |
| `< at(t, Fresh) >` | Typestate Facts (Pre/Post Conditions) | `<at(t, Fresh)> ... <at(t, Once)>` |
| `( x: I64 )` | Runtime Value Arguments | `(x: A)` |

```scala
def report [A: Type] {s: Show[A]} {t: Tape} <at(t, Fresh)> (x: A): I64 <at(t, Once)> =
  s.show(x) + t.read()
```

**Tests:** [`tests/s2/prog/facts.srs`](./tests/s2/prog/facts.srs) (entry and exit state facts), [`tests/s2/prog/facts_vars.srs`](./tests/s2/prog/facts_vars.srs) (variables in facts), [`tests/s2/neg/tf_stale.srs`](./tests/s2/neg/tf_stale.srs) (a fact that no longer holds is rejected).

### 2. Typestate Facts & Datalog Rules
Functions can specify pre- and post-condition facts in `<>`. Protocol definitions can also embed declarative Datalog rules to verify complex state paths:

```scala
protocol Door:
  state Shut, Open1, Open2, Gone
  start Shut
  end Gone
  op knock(): I64 : Shut -> Open1, Open1 -> Open2
  op leave(): Unit : Open1 -> Gone, Open2 -> Gone
  rule def twoKnocks(s, s3) = next(s, knock, s2), next(s2, knock, s3)

def knockTwice {d: Door} <at(d, s), twoKnocks(s, s3)> (): I64 <at(d, s3)> =
  val a = d.knock()
  a + d.knock()
```

**Tests:** [`tests/s2/prog/rules.srs`](./tests/s2/prog/rules.srs) (two rule clauses and recursion over protocol states), [`tests/s2/neg/rule_reach.srs`](./tests/s2/neg/rule_reach.srs) (capability must end in its declared state), [`tests/s2/neg/rule_safety.srs`](./tests/s2/neg/rule_safety.srs) (rule parameter missing from its body).

### 3. Types with Evidence & Compile-Time Computation
Types can be constrained by evidence or state facts, and can compute types at compile time via pure functions:

```scala
type SortedBox [A: Type] {o: Ord[A]} = Box[A]
type OpenFile {f: File} <at(f, Opened)> = Ptr

type Wide [A: Type] = A match
  case Bool => I64
  case I64 => I64

type Bits (n: I64) = n match
  case 8 => Bool
  case _ => I64
```

Pure functions with no side effects can be evaluated at compile time (`--eval` flag). Step budgets ensure compile-time evaluation always terminates safely.

**Tests:** [`tests/s2/prog/type_values.srs`](./tests/s2/prog/type_values.srs) (value parameters on types), [`tests/s2/prog/type_facts.srs`](./tests/s2/prog/type_facts.srs) (state facts carried by types), [`tests/s2/prog/type_evidence.srs`](./tests/s2/prog/type_evidence.srs) (evidence required by types), [`tests/s2/eval/basic.srs`](./tests/s2/eval/basic.srs) (compile-time evaluation), [`tests/s2/neg/tl_fuel.srs`](./tests/s2/neg/tl_fuel.srs), [`tests/s2/neg/tval_fuel.srs`](./tests/s2/neg/tval_fuel.srs), [`tests/s2/eval/neg_fuel.srs`](./tests/s2/eval/neg_fuel.srs) (fuel exhaustion rejected, never treated as unknown).

---

## Content Addressing, C Interop & Contracts

### 1. Content-Addressed Functions (`--hash`)
Functions are hashed by their structural AST behavior rather than their arbitrary names:

```scala
def size(xs: I64): I64 = xs + 1
def len(ys: I64): I64 = ys + 1
// both produce hash: 3664359068.2665956217.563507961.2568932447
```

**Tests:** [`tests/s2/hash/basic.srs`](./tests/s2/hash/basic.srs) (equal and differing hashes), [`tests/s2/hash/valpat.srs`](./tests/s2/hash/valpat.srs) (a val pattern hashes as the match it stands for).

### 2. Foreign C Interop (`extern def`)
Use `extern def` to declare C functions while maintaining full typestate and capability guarantees:

```scala
extern def rt_handle {f: File} <at(f, Opened)> (): OpenFile
```

Generic parameters translate cleanly to `void*` in standard C output.

### 3. Formal Contracts & Proof Hints
srs supports formal specification primitives (`requires`, `ensures`, `invariant`, `decreases`, `proof by induction`, `proof using`) and `spec def` constructs. These facilitate transpilation to Lean 4 for interactive theorem proving.

```scala
spec def size(xs: List): I64
  ensures result >= 0
  proof by induction xs
= xs match
  case Nil => 0
  case Cons(_, t) => 1 + size(t)
```

**Tests:** [`tests/s2/prog/contracts.srs`](./tests/s2/prog/contracts.srs) (contracts parse, check, and erase in C), [`tests/s2/neg/spec_impure.srs`](./tests/s2/neg/spec_impure.srs) (a spec def calls impure code, rejected).

---

## Embedded Logic Engines: miniKanren & Datalog

srs ships with built-in relational programming libraries written directly in srs:

* **miniKanren**: Supports constraint logic programming, unification, disequality (`=/=`), and finite domain constraints (`in`).
* **Datalog**: Features stratified negation, fixpoint evaluation, and full provenance tracking.
* **Type Checker as a Relation**: Demonstrates relational type inference and macro expansion, following the Turnstile model (`turnstile.srs`).

**Tests:** [`tests/s2/prog/kanren_search.srs`](./tests/s2/prog/kanren_search.srs) (search, answer limits, fuel), [`tests/s2/prog/kanren_neq.srs`](./tests/s2/prog/kanren_neq.srs) (disequality), [`tests/s2/prog/kanren_fd.srs`](./tests/s2/prog/kanren_fd.srs) (finite domains with propagation), [`tests/s2/prog/datalog.srs`](./tests/s2/prog/datalog.srs) (transitive closure, stratified negation, negation cycles rejected), [`tests/s2/prog/turnstile.srs`](./tests/s2/prog/turnstile.srs) (type checking as a relation), [`tests/s2/dprov.srs`](./tests/s2/dprov.srs) (rebuilt proof of each derived fact), [`tests/s2/datalog.srs`](./tests/s2/datalog.srs) and [`tests/s2/kfd.srs`](./tests/s2/kfd.srs) (the s2 engines, same answers as s1).

---

## Feature Preview: Relational Macros & Synthesis

Upcoming releases of srs will introduce relational compile-time macros powered by miniKanren:

* **Relational Pattern Macros**: Write code transformation rules via pattern matching and compile-time evaluation (`macro unroll(n: I64, body: Code)`).
* **Type Derivation & Bidirectional Execution**: Generate type encoders/decoders automatically (`json(x)` for encoding, `~json(j)` for decoding).
* **Type-Driven Synthesis**: Synthesize programs automatically from signature types.
* **Variadic Splices (`fs*`)**: Unpack compile-time tuples without runtime list allocations (`case Rect(fs*) => area(fs*)`).

---

## Ecosystem & Test Suite

The test runner validates every feature across positive and negative cases:
* `tests/s2/prog/`: End-to-end programs that s2 must compile, run, and match their expected outputs (`.out`).
* `tests/s2/neg/`: Programs that s2 must reject. Each one names the error code and the exact file and line it expects.
* `tests/s2/eval/` and `tests/s2/hash/`: the compile-time values and the content hashes they must give.
* `tests/s2/*.srs`: tests of the s2 components themselves.
* `tests/s1/` is the suite of the old compiler, removed with it.

---

## Foundations & Literature References

srs builds directly upon landmark research across programming languages, static analysis, and logic systems. Every paper and project referenced in SRS is hyperlinked below:

* **Syntax & Type System**:
  * [Scala 3 Specification](https://docs.scala-lang.org/scala3/) — Surface syntax, given instances, traits, and indentation-based scoping.
  * [Scoped Capabilities for Polymorphic Effects](https://arxiv.org/abs/2207.03402) (*Odersky et al., 2022*) — Capture checking and tracking region capabilities in types.
  * [Gentle Introduction to Second-Class Values](https://www.cs.purdue.edu/homes/rompf/papers/osvald-oopsla16.pdf) (*Osvald et al., OOPSLA 2016*) — Non-escaping capability parameters.
* **Memory Lifetimes & Typestates**:
  * [Region-Based Memory Management](http://web.cs.ucla.edu/~palsberg/tba/papers/tofte-talpin-iandc97.pdf) (*Tofte & Talpin, 1997*) — Stack of regions and static region inference.
  * [Region-Based Memory Management in Cyclone](https://www.cs.umd.edu/projects/cyclone/papers/cyclone-regions.pdf) (*Grossman et al., 2002*) — Explicit region annotations and safe manual deallocation.
  * [Typestate: A Programming Language Concept for Enhancing Software Reliability](https://doi.org/10.1109/TSE.1986.6312929) (*Strom & Yemini, IEEE 1986*) — Foundations of state-dependent protocol checking.
   * [Enforcing High-Level Protocols in Low-Level Software](https://doi.org/10.1145/378795.378811) (*DeLine & Fahndrich, PLLI 2001*) — Vault language and key-tracked resource states.
  * [Modular Typestate Verification of Aliased Objects](http://www.cs.cmu.edu/~kbierhof/papers/typestate-verification.pdf) (*Bierhoff & Aldrich, OOPSLA 2007*) — Access permissions and aliasing control.
  * [fx-rs](https://github.com/denful/fx-rs) — Effect handlers with count and order tracking.
* **Logic Engines, Macro Systems & Error Recovery**:
  * [custom microKanren](http://webyrd.net/scheme-2013/papers/HemannMuKanren2013.pdf) (*Hemann & Friedman, Scheme 2013*) — Core relational unification engine.
  * [Flix Language](https://flix.dev) (*Madsen et al.*) — First-class Datalog constraints embedded in functional syntax.
  * [Better Together: Unification-based Equality Saturation in Egglog](https://arxiv.org/abs/2304.04332) (*Zhang et al., 2023*) — Equality saturation via round-stamp Datalog.
  * [Provenancing Datalog Execution in Souffle](https://arxiv.org/abs/1907.05045) (*Zhao, Subitic & Scholz, 2019*) — Error explanation via Datalog proof derivation graphs.
  * [Total Type Error Localization and Recovery with Holes](https://doi.org/10.1145/3632910) (*Zhao et al., POPL 2024 / Hazel*) — Error localization and recovery via marked lambda calculus.
  * [Type Systems as Macros](https://www2.ccs.neu.edu/racket/pubs/popl17-ckg.pdf) (*Chang, Knauth & Greenman, POPL 2017 / Turnstile*) — Relational macro expansion and type checking as search.
* **Content Addressing, Verification & Runtimes**:
  * [Unison Language](https://www.unison-lang.org) — Content-addressed AST hashing and distributed code distribution.
  * [The Lean 4 Theorem Prover and Programming Language](https://lean-lang.org/papers/lean4.pdf) (*de Moura & Ullrich, 2021*) — Theorem proving target for kernel invariants.
  * [-yen](https://github.com/vic/yen) (*vic*) — Logic programming and Datalog in Nix.
  * [-dnx](https://github.com/denful/dnx) (*denful*) — Next-gen Nix runtime targeting delta interaction nets.

## Support & Development

srs is actively created and maintained by **vic**. If you find srs exciting or want to follow its progress, contributions, issues, and pull requests and [sponsors](https://github.com/sponsors/vic) are warmly welcomed!
