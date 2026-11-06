# srs

srs is a small language with the Scala 3 look and feel that compiles to portable C. There is no garbage collector. Instead, the compiler checks how you use memory, mutable state and resources tracked as Flow Effects with Handlers at compile time, so the C you get has no runtime bookkeeping left in it.

If you write Scala 3 you already know most of the syntax: `enum`, `match`, `trait`, `given`, indentation instead of braces. What srs adds is a type system that tracks *where a value lives* and *what state a resource is in*. It also lets types compute things at compile time.

It is early, and it moves fast. The syntax can still change, and the [tests](tests/) are the best place to see what works today.

## Try it

```console
$ nix develop
$ srs-run hello.srs
24
```

`srs-run` compiles your file together with the prelude, builds the C and runs it. Here is `hello.srs`:

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

The `handle r = Arena()` line is the one new thing here. Values need somewhere to live, so you open a region and the constructors put the nodes in it.

## Regions instead of a GC

A function that builds data says so in its signature with a `{r: Region}` capability. You don't pass it by hand: the nearest region in scope is found for you.

```scala
def build {r: Region} (n: I64): List =
  if n == 0 then Nil else Cons(n, build(n - 1))
```

You can free a region early. The compiler stops you from using a value after its region is gone:

```scala
def main(): I64 =
  handle h = Heap()
  val xs = build(3)
  h.free()
  sum(xs)
```

```console
srs:16: error: use of value after its region ended: 'h'
```

A value that tries to escape its region, or a double free, is rejected the same way.

When there are two regions in scope, the compiler won't guess which one you mean. You name it at the call with `{}`, and that is also where a `var` shows its trick: its region is part of its state, so it moves when you assign it a value from somewhere else.

```scala
def main(): I64 =
  handle a = Arena()
  handle b = Heap()
  // two regions in scope: say which one
  var xs = build{a}(3)
  // xs now lives in b, so freeing a is fine
  xs = build{b}(2)
  a.free()
  sum(xs)
```

Leave out the `{a}` and you get `ambiguous capability, more than one in scope for 'Region'`.

Examples: [region_ok](tests/region_ok.srs), [var_ok](tests/var_ok.srs), [cap_uaf](tests/neg/cap_uaf.srs), [escape](tests/neg/escape.srs), [double_free](tests/neg/double_free.srs).

## Protocols: resources with states

A `protocol` is a small state machine: its states, where it starts and ends, and which ops move it from state to state. A `handler` implements it. When you use one, the compiler follows the state through your code.

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

Leaving before you knock does not compile:

```scala
def main(): I64 =
  handle d = WoodDoor()
  d.leave()
  0
```

```console
srs:15: error: protocol Door: op 'leave' not allowed in state Shut of 'd'
```

Branches that leave a resource in different states are rejected too, and so is a resource that does not reach its end state. Files, locks and sockets are what this is for: [file.lib](tests/file.lib) defines a `File` protocol and [file_ok](tests/file_ok.srs) uses it. The tests that must fail: [close_no_read](tests/neg/close_no_read.srs) and [branch_state](tests/neg/branch_state.srs).

## Facts: functions that know about states

This is the part I find most fun. A function can state facts in `<>`: the facts it needs when you call it, and, after the return type, the facts it leaves behind. Facts can have variables, so one function can work across many states. Here is a tape you can read twice, and a `readAny` that reads from whatever state it finds the tape in:

```scala
protocol Tape:
  state Fresh, Once, Twice, Done
  start Fresh
  end Done
  op read(): I64 : Fresh -> Once, Once -> Twice
  op stop(): Unit : Once -> Done, Twice -> Done

// works from any state s that has a read, and leaves the tape in the state after it
def readAny {t: Tape} <at(t, s), next(s, read, s2)> (): I64 <at(t, s2)> = t.read()

def main(): I64 =
  handle t = MemTape()
  val a = readAny()
  val b = readAny()
  t.stop()
  a + b
```

The compiler checks the body of `readAny` once for every state it can start from. At each call it works out where the tape is and moves it one step on. A third `readAny()` fails, because a tape in `Twice` has no read left:

```console
srs:19: error: entry facts do not hold at the call of 'readAny'
```

Examples: [facts_vars](tests/facts_vars.srs), [facts](tests/facts.srs), [fact_entry](tests/neg/fact_entry.srs), [fvar_exit](tests/neg/fvar_exit.srs).

<details>
<summary>Rules: name a path through a protocol</summary>

A protocol can carry its own rules, written as Datalog, and functions can use them in their facts. Rules can have more than one clause, and they can be recursive.

```scala
protocol Door:
  state Shut, Open1, Open2, Gone
  start Shut
  end Gone
  op knock(): I64 : Shut -> Open1, Open1 -> Open2
  op leave(): Unit : Open1 -> Gone, Open2 -> Gone
  rule def twoKnocks(s, s3) = next(s, knock, s2), next(s2, knock, s3)

// enters with the door in s, leaves it in s3, two knocks later
def knockTwice {d: Door} <at(d, s), twoKnocks(s, s3)> (): I64 <at(d, s3)> =
  val a = d.knock()
  a + d.knock()
```

Examples: [rules](tests/rules.srs) (a recursive `reach`), [rule_reach](tests/neg/rule_reach.srs).

</details>

## Generics, traits and givens

Type parameters go in `[]`, as in Scala 3. Evidence, like a `Show[A]` instance, goes in `{}` and always has a name. A `given` can depend on other givens, so `Show[Box[A]]` holds when `Show[A]` does.

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

Then `print(Box(41))` finds the evidence for you and prints `141`. Local evidence comes before a global given, and a more specific given wins over a general one, as in Scala 3. When two givens are equally good, the compiler does not pick one for you: it rejects the call as ambiguous.

Examples: [generic_enum](tests/generic_enum.srs), [givens](tests/givens.srs), [given_local](tests/given_local.srs), [given_rank](tests/given_rank.srs), [given_ambig](tests/neg/given_ambig.srs).

## Types that carry evidence and facts

The same `{}` and `<>` groups work on types. A `SortedBox[A]` is a plain `Box[A]`, but you can only name it where an `Ord[A]` exists:

```scala
type SortedBox [A: Type] {o: Ord[A]} = Box[A]

def first [A: Type] {o: Ord[A]} (b: SortedBox[A]): A = b match
  case Box(v) => v

def main(): I64 =
  handle r = Arena()
  val b: SortedBox[I64] = Box(41)
  first(b) + 1
```

Ask for a `SortedBox[Bool]` and the compiler answers `no given for Ord[Bool]`.

Facts on a type work the same way: an `OpenFile` can be a plain pointer that you can only use while its file is still open.

```scala
type OpenFile {f: File} <at(f, Opened)> = Ptr
```

Examples: [type_evidence](tests/type_evidence.srs), [type_facts](tests/type_facts.srs).

## Types that compute

Types can match on types, and they can take plain values that are known at compile time:

```scala
type Wide [A: Type] = A match
  case Bool => I64
  case I64 => I64

type Bits (n: I64) = n match
  case 8 => Bool
  case _ => I64

def flag(x: Bits(8)): Bool = x
def word(x: Bits(32)): I64 = x + 1
```

The value inside `Bits(...)` can also be a call: `Bits(dbl(4))` works when `dbl` is a pure function, because srs runs pure functions at compile time. Type-level work always ends with an answer: a search that runs out of steps is a compile error, never a "maybe".

Examples: [typelambda](tests/typelambda.srs), [type_values](tests/type_values.srs), [compile-time evaluation](tests/eval/basic.srs).

<details>
<summary>Contracts and proofs</summary>

`requires`, `ensures`, `invariant` and `decreases` are part of the syntax, together with proof hints. A `spec def` exists only for proofs and specs, and it may only call pure functions. The C output does not contain any of this.

```scala
spec def size(xs: List): I64
  ensures result >= 0
  proof by induction xs
= xs match
  case Nil => 0
  case Cons(_, t) => 1 + size(t)

def count(xs: List): I64
  ensures result == size(xs)
  proof using size
=
  var c = xs
  var n = 0
  while c match
    case Nil => false
    case Cons(_, _) => true
  do
    invariant n + size(c) == size(xs)
    decreases size(c)
    c = c match
      case Nil => c
      case Cons(_, t) => t
    n = n + 1
  n
```

Examples: [contracts](tests/contracts.srs), [purity](tests/purity.srs).

</details>

<details>
<summary>Logic programming in the box: Kanren and Datalog</summary>

The standard libraries include a miniKanren (with constraints) and a Datalog with stratified negation, both written in srs, and you can use them in your own programs.

Examples: [kanren_search](tests/kanren_search.srs) runs `appendo` both ways, [datalog](tests/datalog.srs) computes a transitive closure, and [turnstile](tests/turnstile.srs) writes a small type checker as a Kanren relation.

</details>

## More examples

Every file in [tests/](tests/) is a program that must compile and run, and its expected output is in the `.out` file next to it. Every file in [tests/neg/](tests/neg/) must be rejected, and its first lines say with which error. Read the two folders side by side: that is the most complete tour of the language right now.

## Sponsor Development

srs is made with love by [vic](https://github.com/vic). A language with no GC, where memory, state and resources are checked before the program runs, takes a lot of patient work to get right. If srs is useful to you, or you want to see where it goes, please [sponsor vic](https://dendritic.oeiuwq.com/sponsor). Issues and pull requests are welcome.
