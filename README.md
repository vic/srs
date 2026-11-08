# srs: Scala 3 Syntax Meets Zero-GC C

Welcome to **srs**—a small, modern systems programming language designed to give you the clean expression of Scala 3 with the bare-metal performance and predictable memory footprint of C. 

The compiler is self-hosting (written in srs itself in `./s1`) and builds via a minimal Zig toolchain bootstrap. Rather than relying on a garbage collector, srs verifies memory lifetimes, mutable state, and custom resource transitions entirely at compile time using algebraic flow effects and typestate protocols. The compiled output is clean, portable C with zero runtime bookkeeping overhead.

---

## Why SRS?

If you love high-level functional programming but need tight control over performance and resources, srs was built for you:

* **Scala 3 Design, C Execution**: Enjoy `enum`, `match`, `trait`, `given`, and clean whitespace-based indentation, compiling directly to any C target.
* **Algebraic Effects for Memory & Resources**: Inspired by structural Algebraic Effects with Handlers [fx-rs](https://github.com/denful/fx-rs), Tofte-Talpin region inference, Cyclone, and capture checking. Memory and state management are modeled as effects with handlers.
* **Content-Addressed Execution**: Following Unison and Nix derivations, functions and values are named by the cryptographic hash of their abstract syntax tree (AST) and effect requirements. Code can be cached in a global Nix-style store, shared across workspace agents without re-compilation, and hot-patched live.
* **Formal Verification**: Compiles to both C for production binaries and Lean 4 for proving kernel invariants.
* **Real-World Mission**: Built to power [`dnx`](https://github.com/denful/dnx), a next-generation Nix runtime executing on delta interaction nets.

---

## Compiler Roadmap: s1 & s2

The project is actively evolving across two compiler iterations:

| Compiler Version | Design Architecture | Error Handling & Capabilities |
| :--- | :--- | :--- |
| **s1 (Current)** | Imperative (`var`, `while`), written in srs to bootstrap the language. | Fast initial bootstrap; stops at the first encountered compile error. |
| **s2 (In Progress)** | Purely functional (`val`, recursion), Datalog-backed constraint engine. | Reports all errors simultaneously, derives fixpoint branch joins automatically, and provides full error provenance (*why* an error occurred). |

The foundation libraries powering s2 live in `s2/` (including persistent collections, miniKanren with disequality, and Datalog with stratified negation).

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

---

## Content Addressing, C Interop & Contracts

### 1. Content-Addressed Functions (`--hash`)
Functions are hashed by their structural AST behavior rather than their arbitrary names:

```scala
def size(xs: I64): I64 = xs + 1
def len(ys: I64): I64 = ys + 1
// both produce hash: 3664359068.2665956217.563507961.2568932447
```

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

---

## Embedded Logic Engines: miniKanren & Datalog

srs ships with built-in relational programming libraries written directly in srs:

* **miniKanren**: Supports constraint logic programming, unification, disequality (`=/=`), and finite domain constraints (`in`).
* **Datalog**: Features stratified negation, fixpoint evaluation, and full provenance tracking.
* **Type Checker as a Relation**: Demonstrates relational type inference and macro expansion, following the Turnstile model (`turnstile.srs`).

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
* `tests/`: End-to-end code examples that must compile and match expected outputs (`.out`).
* `tests/neg/`: Rejection test suite verifying precise compile errors.

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
