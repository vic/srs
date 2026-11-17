# srs

srs is a systems language with a Scala 3 surface that compiles to portable C. It has no garbage collector. Memory lives in regions, effects are capabilities that callers must handle, and the compiler proves memory safety before it emits code. A program that it cannot prove safe does not compile.

## Programs are named units

A program is a set of named units: definitions, values, types, enums, traits, givens, capabilities, handlers, externs and C structs. A name can contain dots, such as `Geo.Point.dist`, and every unit can use every other unit by its full name, so there are no imports. Inside a unit, an alias gives a long name a short local form:

```scala
alias A = Ar
def Geo.first(n: I64, xs: Array[I64](n)): I64 = A.at(n, xs, 0)
```

Blocks use indentation. `val` binds an immutable value and `var` binds a variable. `if`/`then`/`else`, `match`/`case` and `while`/`do` are expressions or statements as in Scala 3.

## Types

The built-in types are the integers `I64`, `U8`, `U32` and `U64`, `Bool`, `Str`, `Unit` and `Never`. An integer literal must fit its type. Integer literals can be decimal or hexadecimal.

An enum declares cases, each with its own fields. Enums can take type parameters:

```scala
enum Opt [A: Type]:
  case None
  case Some(v: A)
```

A `match` selects on the case of a value, and `_` matches any case. Patterns match one level of a value; a field that is itself an enum is matched in a second `match`. A `val` can also take a value apart:

```scala
val Pair(a, b) = p
```

Definitions are generic over types with binders such as `[A: Type]`. The compiler infers type arguments at a call and rejects a call whose type arguments it cannot infer.

## Types that carry values

Types can take values as parameters, and a type definition can compute its result from them at compile time:

```scala
type Cell.Of (wide: Bool) = wide match
  case true => I64
  case _ => U8
```

Top-level values are compile-time constants. Pure functions can run at compile time to compute the arguments of a type, with a bounded amount of work. A function that has effects cannot run at compile time.

## Arrays and proofs

An array type names its length: `Array[I64](n)` holds exactly `n` elements. `Array.fill(n, v)` makes an array of `n` copies of `v`, and `Array.tabulate` builds one from a generator. An index is accepted only when the compiler can prove that it is inside the length, usually from a condition that guards it:

```scala
def Ar.at(n: I64, xs: Array[I64](n), i: I64): I64 =
  if 0 <= i && i < n then xs(i) else 0
```

Slices, copies between arrays and growth copies need the same kind of proof for their offsets and lengths.

## Regions

Every allocation belongs to a region. You open a region with `handle`, and freeing it ends every value in it:

```scala
def main(): I64 =
  handle r = Srs.Arena()
  val n = 4
  val xs = Array.fill(n, 7)
  val first = Ar.at(n, xs, 0)
  r.free()
  first
```

`Srs.Arena` gives a region that frees all its memory at once, and `Srs.Heap` gives one that allocates each block on its own. A function that allocates states the region it needs as a binder, `{r: Srs.Region}`, and the caller provides it implicitly from a region in scope or explicitly as `build{a}(3)`.

The compiler rejects every program that:

- uses a value after its region is freed,
- allocates in a region that is already freed or frees a region twice,
- returns or stores a value in a place that lives longer than its region.

## Mutation and atomics

Mutation is an effect. Writing into an array or a `Cell` needs the `Srs.Mut` capability in scope, and atomic access needs `Srs.Atomic`. A `Cell` holds one value that can change; a value put into a cell must live at least as long as the cell. Code without these capabilities cannot change shared state.

## Capabilities and handlers

A capability declares operations. A function that needs one states it as a binder, and a caller provides it with `handle` and a handler:

```scala
capability Log:
  def say(n: I64): Unit

handler Quiet for Log:
  def say(n: I64): Unit = ()

def work {l: Log} (): I64 =
  l.say(1)
  0

def main(): I64 =
  handle q = Quiet()
  work()
```

A call that needs a capability must have exactly one provider in scope at that point. Console output, processes, the network, clocks, environment variables, files and memory pages are capabilities too, so a program cannot reach the outside world without a handler for it.

Handlers can keep state. A handler operation can capture the rest of the computation as a continuation `k` and resume it zero, one or many times, which gives generators, backtracking and search:

```scala
handler AllAnswers [A: Type] for NonDet:
  def choose(k): A = resume k(true)
```

## Protocols

A capability can declare states and the transitions of its operations. The compiler then checks the order of operations on every path of the program:

```scala
capability Door:
  state Shut, Open1, Open2
  start Shut
  stop Open2
  transition knocks Shut -> Open1, Open1 -> Open2
  def knock <s knocks t> (): I64 <t>
```

Every operation must be allowed in the state that the capability has at that point, on every path through branches and loops. Every capability must reach a stop state before its scope ends.

A function can state facts about the capabilities it receives and the state in which it leaves them:

```scala
def once {d: Door} <d: Shut> (): I64 <d: Open1> = d.knock()
```

A capability can also define rules, written as logic clauses over its transitions, and a function can use these rules in its facts:

```scala
rule def reach(s, t) = next(s, knock, t)
rule def reach(s, t) = next(s, knock, u), reach(u, t)
```

## Traits and givens

A trait declares methods over a type. A given provides those methods for a concrete type, and a function receives them as an evidence binder:

```scala
trait Show [A: Type]:
  def show(x: A): Str

def Text.line [A: Type] {s: Show[A]} (x: A): Str = s.show(x)
```

The compiler finds the given for each call. It rejects a call with no matching given, and it rejects two givens that match the same call.

## C interop

`extern "libc" def` declares a C function. Externs are typed, a generic extern slot takes only pointer-like values, and C calls are allowed only inside handlers, so user code reaches C only through a capability. A C struct declaration gives the fields and layout of a C record. Raw pointers do not exist in user code.

## Tests in the language

Tests are values. A test is a value of capability `Test`, and the compiler computes it:

```scala
val Tests.add {Test}: Test.Result = Test.expect(2 + 3, 5, "integer addition")
```

A negative test holds a small program and the error codes with which the compiler must reject it:

```scala
val NegTests.doubleFree {NegTest}: Never =
  def main(): I64 =
    handle r = Srs.Arena()
    r.free()
    r.free()
    0
  NegTest.expect("op-not-allowed", "a freed region allows no second free")
```

## Errors

Each rejection has a named code, such as `error[use-after-free]`, `error[index-unproved]` or `error[op-not-allowed]`, and names the definition that caused it.
