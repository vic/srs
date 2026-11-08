# srs

srs is a small language with the Scala 3 look and feel that compiles to portable C. It is implemented in [itself `./s1`](./s1), bootstrapped via the Zig toolchain using a stable [seed](./bootstrap). There is no garbage collector. Instead, the compiler checks how you use memory, mutable state and resources tracked as Flow Effects with Handlers at compile time, so the C you get has no runtime bookkeeping left in it.

> Why?
>
> My goal is to create a better Rust for myself and perhaps also for you. I have always loved Scala3 type-system and have
> also been exploring [algebraic effects with handlers](https://github.com/denful/fx-rs) -particularly on the area of effect
> quantification and ordering- that of course can be applied to linearity and memory management. I'm also a big fan of [Unison](https://www.unison-lang.org) and [Flix](https://flix.dev) both are great inspiration to this experiment. I've also been working
> on [logic programming in Nix](https://github.com/vic/yen) and that is also and inspiration on using Datalog at the type-system.

> What does all this means, practially?
>
> That we can have a high-level functional language compiled directly to any C target, with much better resource management
> via handlers and effects and type protocols (see below). 
>
> Sharing functions by their content hash is an idea I've learned from Unison an Nix, that means we can have a common "store"
> of pre-compiled functions we can re-use. That is suitable for multi-workspace agentic workflows that can share computations
> between them instead of `./target` and all deps being recompiled each time.
>
> Protocols allows to express state machines on resources. Regions (memory management) is the primary use-case, but they will
> be useful for any resource that is stateful (db-transactions, etc).


If you write Scala 3 you already know most of the syntax: `enum`, `match`, `trait`, `given`, indentation instead of braces. What srs adds is a type system that tracks *where a value lives* and *what state a resource is in*. It also lets types compute things at compile time.

It is early, and it moves fast. The syntax can still change, and the [tests](tests/) are the best place to see what works today.

This README starts with what will feel familiar and goes a step further in each section, so reading it top to bottom is a good way to meet the language.

<details>
<summary>Where we are</summary>

The compiler you can run today is s1. It compiles itself, and everything shown here works in it, except the macros section at the end. s1 was written in a hurry to get the language off the ground: it is imperative inside (`var` and `while` everywhere), and it stops at the first error.

Now I'm writing s2, the compiler that will replace s1. It is written in srs in a functional style (only `val`, no loops, only recursion), and speed comes first. Its checker will be a Datalog program: protocol states, regions and `var` tracking become facts, the rules derive what holds at each point of a function, and a type error is a fact too. That gives three things s1 does not have: every error is reported, not only the first one; the joins at branches and loops come from the Datalog fixpoint instead of hand-written code; and each error will be able to say *why*, because every derived fact will remember the rule that made it.

The pieces it stands on are in [s2/](s2): collections, a miniKanren with disequality and finite domains, and a Datalog with stratified negation. They give the same answers as the libraries in [lib/](lib) and are much faster. The checker itself is being ported from s1 one part at a time: first protocol states, then regions and vars, then names, purity, the parser, types and generics.

</details>

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

The `handle r = Arena()` line is the one new thing here. Values need somewhere to live, so you open a region and the constructors put the nodes in it. We will come back to regions soon.

## Pattern matching checks every case

A `match` has to cover every case of the enum. Add a new case, and the compiler shows you each place that does not handle it yet:

```scala
enum Light:
  case Red
  case Yellow
  case Green

def wait(l: Light): I64 = l match
  case Red => 30
  case Yellow => 5
```

```console
srs:6: error: match is not exhaustive, missing case 'Green'
```

A `match` is an expression, so it can go anywhere a value can, even as the condition of a loop: `while c match` with `case Nil => false` and `case Cons(_, _) => true` loops until the list is empty. You will see one in the contracts section.

## Generic enums and type aliases

Type parameters go in `[]`, as in Scala 3, and enums can have them too:

```scala
enum Opt [A: Type]:
  case None
  case Some(v: A)

enum Pair [A: Type] [B: Type]:
  case Pair(a: A, b: B)

def get [A: Type] (o: Opt[A], d: A): A = o match
  case None => d
  case Some(v) => v

def first [A: Type] [B: Type] (p: Pair[A, B]): A = p match
  case Pair(a, _) => a
```

Type arguments are found from the arguments, or from the type you expect back: `val n: Opt[I64] = None` is enough for `None`. Nesting is fine, so `Pair(Some(7), false)` is a `Pair[Opt[I64], Bool]`. You can also give them by hand with `id[I64](41)`. Each use with a new type gets its own copy in C, so generic code costs nothing at run time. You pay for it in code size and compile time instead.

Type aliases work as you expect, with or without parameters, and they can use each other:

```scala
type Id [A: Type] = A
type Num = I64
type Maybe [A: Type] = Opt[Id[A]]

val m: Maybe[Num] = Some(1)
```

Mixing them up is a plain type error, such as `type mismatch: Opt[I64] is not Opt[Bool]`.

Examples: [generic](tests/generic.srs), [generic_enum](tests/generic_enum.srs), [typelambda](tests/typelambda.srs), [genum_mismatch](tests/neg/genum_mismatch.srs).

## Traits and givens

Evidence, like a `Show[A]` instance, goes in `{}` and always has a name. A `given` can depend on other givens, so `Show[Box[A]]` holds when `Show[A]` does.

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

Then `print(Box(41))` finds the evidence for you and prints `141`. Evidence is found by its type, as in Scala 3. The name is there so you can also hand it over yourself: a function that holds `{s: Show[A]}` can call `print{s}(x)`. Local evidence comes before a global given, and a more specific given wins over a general one, as in Scala 3. When two givens are equally good, the compiler does not pick one for you: it rejects the call as ambiguous. A set of givens that would search forever is stopped too, with `given search ran out of fuel`.

Examples: [traits](tests/traits.srs), [givens](tests/givens.srs), [given_local](tests/given_local.srs), [given_rank](tests/given_rank.srs), [given_ambig](tests/neg/given_ambig.srs), [given_fuel](tests/neg/given_fuel.srs).

## Regions instead of a GC

Back to regions. A function that builds data says so in its signature with a `{r: Region}` capability: the same `{}` as evidence, because holding a region is a kind of evidence too. You don't pass it by hand: the nearest region in scope is found for you.

```scala
def build {r: Region} (n: I64): List =
  if n == 0 then Nil else Cons(n, build(n - 1))
```

You can free a region early. A region is a resource with states, open or freed (the protocols section shows how that works), and the compiler stops you from using a value after its region is gone:

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

How can this work with aliasing? Because the unit you free is a whole region, never a single object. The region is part of a value's type, so every alias of a value names the same region: free it, and every alias is dead at once. An escape is a value whose type names a region that has already ended. The region capability itself can't be aliased: it is second-class, so it can only be a parameter or a `handle`, never stored in data, returned, or passed twice to one call. The flip side: you can't free one object out of a region.

You can write the region down when you want to be explicit. `^<r>` says "this lives in `r`":

```scala
val q: Opt[I64]^<r> = Some(5)
```

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

Leave out the `{a}` and you get `ambiguous capability, more than one in scope for 'Region'`. The compiler follows a `var` through every branch and around every loop, so a value that only moves into a freed region on the second turn of a loop is still caught. This always finishes: a `var` can only hold the regions in scope, so going around the loop again stops adding anything after a few turns. The check is conservative, it rejects what it can't prove safe, so now and then a correct program is rejected too.

Examples: [region_ok](tests/region_ok.srs), [var_ok](tests/var_ok.srs), [cap_uaf](tests/neg/cap_uaf.srs), [escape](tests/neg/escape.srs), [var_branch](tests/neg/var_branch.srs), [var_loop](tests/neg/var_loop.srs).

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

Forget to leave and you hear about that too: `'d' ends its scope in state Open, not an end state`. Branches that leave a resource in different states are rejected as well, and a loop must leave every resource in the state it found it in. This is typestate, an idea from the 80s. Vault, and later the access permissions of Bierhoff and Aldrich, showed how to make it work when many names point at one resource. srs keeps it simple by never letting two names share one. Files, locks and sockets are what this is for: [file.lib](tests/file.lib) defines a `File` protocol and [file_ok](tests/file_ok.srs) uses it. The tests that must fail: [close_no_read](tests/neg/close_no_read.srs) and [branch_state](tests/neg/branch_state.srs).

<details>
<summary>Regions are protocols too: bring your own allocator</summary>

Now the region from the first example makes sense. `Region` is a protocol in the prelude, and `Arena` and `Heap` are two handlers of it. Write your own handler and it works everywhere a region does:

```scala
handler Bump for Region:
  def init(): Ptr = rt_arena_new()
  def alloc(self: Ptr, size: I64): Ptr = rt_arena_alloc(self, size)
  def free(self: Ptr): Unit = rt_arena_free(self)

def main(): I64 =
  handle b = Bump()
  val n = sum(build(4))
  b.free()
  n
```

Because it is a protocol, freeing twice or allocating after a free is a state error: `op 'free' not allowed in state Freed`. See [double_free](tests/neg/double_free.srs) and [alloc_after_free](tests/neg/alloc_after_free.srs).

</details>

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

A protocol can carry its own rules, written as Datalog, and functions can use them in their facts. Rules can have more than one clause, and they can be recursive. They always finish: the states of a protocol are a fixed set, so there are only so many facts to find. A rule has no inputs or outputs either. `twoKnocks(s, s3)` is true for every pair of states two knocks apart, and `s2` is just a name for the state in the middle.

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

The value is whatever the two knocks return added up: with a handler whose `knock` returns `3`, that is `6`. The facts only say where the door is before and after.

Examples: [rules](tests/rules.srs) (a recursive `reach`), [rule_reach](tests/neg/rule_reach.srs).

</details>

## Signatures are telescopes

By now you have met four kinds of brackets in a signature, and they all belong to one idea. Everything a function needs is in its signature, written as a row of groups, and each kind of bracket asks for one kind of thing:

- `(x: I64)`: values, as usual.
- `[A: Type]`: types. `A` is a name, and `Type` is what it is.
- `{s: Show[A]}`: evidence and capabilities. Proof that `Show[A]` exists, or a region or a file you hold. These always have a name.
- `<at(t, Fresh)>`: facts, the states your resources must be in. Facts after the return type are the states you leave them in.

The row reads left to right like a telescope: each group can use the names of the groups before it. Here `A` is used by the evidence, the tape `t` is used by the facts, and the values come last:

```scala
def report [A: Type] {s: Show[A]} {t: Tape} <at(t, Fresh)> (x: A): I64 <at(t, Once)> =
  s.show(x) + t.read()

def main(): I64 =
  handle t = MemTape()
  val n = report(35)
  t.stop()
  n
```

At a call you usually pass only the values: the compiler finds the type, the evidence and the tape for you, and it checks the facts. You can also spell the groups out yourself, as you saw earlier: `report[I64](35)` gives the type, and `build{a}(3)` picks the region by name.

The same groups work on types, which is the next section. A `spec def`, which only exists for proofs, takes no groups at all. An `extern def`, which is a C function, takes all of them, and its telescope is a contract that the compiler trusts.

## Types that carry evidence and facts

The `{}` and `<>` groups work on types too. A `SortedBox[A]` is a plain `Box[A]`, but you can only name it where an `Ord[A]` exists:

```scala
given Ord[I64]:
  def lt(a: I64, b: I64): Bool = a < b

type SortedBox [A: Type] {o: Ord[A]} = Box[A]

def first [A: Type] {o: Ord[A]} (b: SortedBox[A]): A = b match
  case Box(v) => v

def main(): I64 =
  handle r = Arena()
  val b: SortedBox[I64] = Box(41)
  first(b) + 1
```

There is a given for `I64` and none for `Bool`, so ask for a `SortedBox[Bool]` and the compiler answers `no given for Ord[Bool]`.

Facts on a type work the same way: an `OpenFile` can be a plain pointer that you can only use while its file is still open.

```scala
type OpenFile {f: File} <at(f, Opened)> = Ptr
```

Examples: [type_evidence](tests/type_evidence.srs), [type_facts](tests/type_facts.srs).

## Types that compute

Types can match on types, and with a `()` group they can take plain values that are known at compile time:

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

The value inside `Bits(...)` can also be a call: `Bits(dbl(4))` works when `dbl` is a pure function. A function that prints or allocates can't go there, and the compiler tells you why: `comptime call of a fn with effects: 'noisy'`. Type-level work always ends with an answer: a search that runs out of steps is a compile error, never a "maybe".

To be clear about what that means: pure is not enough for a function that computes a type, it also has to end. srs does not prove that yet. It runs the function on a step budget, and a function that needs more steps than the budget is rejected, even when it would have finished. So the budget keeps the compiler from hanging, but it is not a proof. A real termination check is on the list (size-change termination is the one I'm looking at).

Examples: [typelambda](tests/typelambda.srs), [type_values](tests/type_values.srs), [tval_impure](tests/neg/tval_impure.srs).

## Pure functions run at compile time

That `dbl(4)` above ran while the program compiled. You don't mark functions as pure: a function with no effects in its signature or its body is pure, and the compiler can run it. You can try it yourself with `--eval`, which prints every pure constant:

```scala
def square(x: I64): I64 = x * x

def sumTo(n: I64): I64 =
  var i = 0
  var s = 0
  while i < n do
    i = i + 1
    s = s + i
  s

def nine(): I64 = square(3)
def ten(): I64 = sumTo(4)
```

```console
$ srs=$(srs-build)
$ $srs --eval lib/prelude.srs consts.srs
nine 9
ten 10
```

A loop that runs past the step budget, or a division by zero, is a compile error, not a hang: `comptime division by zero in 'half'`.

Examples: [eval/basic](tests/eval/basic.srs), [purity](tests/purity.srs), [eval/neg_fuel](tests/eval/neg_fuel.srs).

## A function is its content

Each definition gets a hash of what it *does*, not of what it is called. Local names don't count, and a call counts by the hash of the function it calls, not by its name. So two functions that only differ in names have the same hash:

```scala
def size(xs: I64): I64 = xs + 1
def len(ys: I64): I64 = ys + 1
def bigger(xs: I64): I64 = xs + 2
```

```console
$ $srs --hash names.srs
size 3664359068.2665956217.563507961.2568932447
len 3664359068.2665956217.563507961.2568932447
bigger 1801594593.1269715932.528174218.3540524843
main 966297948.1643762100.2234580799.1926270718
```

This is the idea from Unison, and it is the ground for caching compiled code by content. Example: [hash/basic](tests/hash/basic.srs).

## Talking to C

`extern def` declares a C function. Because it takes the full telescope, you can describe what the C side does to your resources, and the compiler holds every caller to it. This one hands out an `OpenFile`, and only while the file is open:

```scala
extern def rt_handle {f: File} <at(f, Opened)> (): OpenFile
```

Generic externs work too. A value of a type parameter is passed to C as a `void*`, so one C symbol serves every type. See [generic](tests/generic.srs) and [type_facts](tests/type_facts.srs).

## Contracts and proofs

`requires`, `ensures`, `invariant` and `decreases` are part of the syntax, together with proof hints. A `spec def` exists only for proofs and specs, and it may only call pure functions. The C output does not contain any of this. s1 can turn them into Lean 4 theorems about its own code, but that work is paused until s2 is in place, so read this section as an early sketch.

<details>
<summary>An example: counting a list, with a loop invariant</summary>

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

Specs can quantify, too. This one says that after a `push`, a value is in the list exactly when it is the new head or was there before:

```scala
def push {r: Region} (h: I64, xs: List): List
  ensures forall v: I64 => memL(v, result) == (h == v || memL(v, xs))
  proof using memL
= Cons(h, xs)
```

</details>

Examples: [contracts](tests/contracts.srs), [spec_impure](tests/neg/spec_impure.srs).

## Logic programming in the box

The last stop is the deep end. The standard libraries include a miniKanren and a Datalog, both written in srs, and you can use them in your own programs. srs has no closures, so goals and rules are plain data that you build and then solve.

<details>
<summary>miniKanren with constraints</summary>

Unification, disequality (`=/=`) and finite domains are all there. Two numbers in `1..3` where the first is smaller:

```scala
def main(): I64 =
  handle r = Arena()
  val x = TVar(0)
  val y = TVar(1)
  // x and y in 1..3, x < y: every pair
  val goal = both(both(both(in(x, 1, 3), in(y, 1, 3)), lt(x, y)), GLabel(two(x, y)))
  solve(RNil, goal, 2, 1000, 10) match
    case Run(ans, _) => showPairs(ans)
  0
```

```console
$ srs-run lib/kanren.srs pairs.srs
2 < 3
1 < 2
1 < 3
```

`both`, `in`, `lt` and `two` are one-line helpers that build the goals. Every search runs on fuel, so a goal that would loop forever stops and says so. "Out of fuel" means "no answer within the budget", not "this would never end". Relations run both ways: [kanren_search](tests/kanren_search.srs) asks `append` which two lists give `[a, b]` and gets all three answers.

More: [kanren](tests/kanren.srs) (unify), [kanren_neq](tests/kanren_neq.srs) (disequality), [kanren_fd](tests/kanren_fd.srs) (finite domains).

</details>

<details>
<summary>Datalog with stratified negation</summary>

```
path(X, Y) :- edge(X, Y).
path(X, Z) :- edge(X, Y), path(Y, Z).
```

Over the edges `a -> b -> c -> d` this gives:

```console
path(a, b) path(b, c) path(c, d) path(a, c) path(b, d) path(a, d)
```

Negation works as long as it does not go around in a cycle. For a cycle, or a rule with a variable that nothing binds, you get that answer back instead of a result: `negcycle p` or `unsafe p`. A result also comes with a checker: give it a forged fact and it points at it, `invalid edge(x, y)`. See [datalog](tests/datalog.srs).

A bare "no" from a logic program is hard to debug. So the s2 Datalog will keep, for every fact, the rule that made it. Then an error can show its proof: which steps put a resource in which state, and where two of them disagree. That is the idea from Soufflé's provenance.

</details>

<details>
<summary>A type checker as a relation</summary>

[turnstile](tests/turnstile.srs) writes a small type checker as one Kanren relation, with one clause per kind of expression. A single run gives back both the type and the expanded code:

```console
cif(cvar(b), cint(1), cint(2)) : I64
ccall(f, cadd(cvar(x), cint(1))) : Bool
reject: ambiguous
```

This is the direction the language itself is going: type checking and code expansion as one search. The idea comes from Turnstile, [Type Systems as Macros](https://www2.ccs.neu.edu/racket/pubs/popl17-ckg.pdf) by Chang, Knauth and Greenman.

</details>

## Coming next: macros and synthesis

This part is designed but not in the compiler yet, so treat the syntax as a preview.

A macro in srs is not a template and it does not glue strings together. It is a relation, solved by the same miniKanren you saw above. You write its clauses with the `case` syntax you already know, a call is a goal, and the answer to the goal is the code that replaces the call. A clause can match literals, bind variables, repeat a variable to ask that two arguments are equal, and add an `if` guard:

```scala
macro unroll(n: I64, body: Code): Code =
  case (0, _) => ()
  case (n, body) if n > 0 =>
    body
    unroll(n - 1, body)

def main(): I64 =
  unroll(1 + 2, rt_print("hi\n"))
  0
```

`n` is worked out at compile time, so `unroll(1 + 2, ...)` becomes three prints in a row, with no loop left in the C. If no clause fits, or two do, the call is an error. A macro that keeps expanding runs out of fuel and stops, like every other compile-time search in srs.

The important part is that type checking happens inside that search, not in a second pass after it. A clause whose code does not type-check at the call site is a dead end, so the search moves on to the next clause. That is also why errors are becoming plain data inside the compiler: a failed check has to be something the search can look at, not something that stops the program.

The same machinery gives you three more things that Scala 3 people usually reach for macros or derivation for:

- **Derivation.** A macro can look at the shape of a type: its cases and their fields. A `json` macro can then write the encoder for your enum. The result is data, a `Json` value built from your cases, never a string template.
- **Both directions.** A relation can run both ways, so clauses that encode can often decode too. You write the backwards call with a `~`: `json(x)` encodes and `~json(j)` decodes. Not every macro can be run backwards, and decoding can fail, so `~json` gives you an `Option`.
- **Synthesis.** Run the search from a type instead of a call, and miniKanren looks for a program of that type, built from what is in scope: constructors, matches, your functions and givens. It takes the first answer it finds in a fair search order, so the result is always the same, and it gives up when it runs out of fuel.

Splices come with this, as a language feature and not only for macros. `fs*` stands for a group of arguments whose count is known at compile time. It expands in place, with no list and no allocation, and each position keeps its own type:

```scala
def area(w: I64, h: I64): I64 = w * h

def f(r: Rect): I64 = r match
  case Rect(fs*) => area(fs*)   // becomes area(w, h)
```

## More examples

Every file in [tests/](tests/) is a program that must compile and run, and its expected output is in the `.out` file next to it. Every file in [tests/neg/](tests/neg/) must be rejected, and its first lines say with which error. Read the two folders side by side: that is the most complete tour of the language right now.

## Where the ideas come from

srs takes a lot from other people's work, and I want to say so. The surface is [Scala 3](https://docs.scala-lang.org/scala3/), and effects with handlers come from my own [fx-rs](https://github.com/denful/fx-rs). Regions come from Tofte and Talpin's region inference and from [Cyclone](https://www.cs.umd.edu/projects/cyclone/papers/cyclone-regions.pdf) (Grossman et al.). Regions in types are capture sets, as in Scala 3 capture checking ([Scoped Capabilities for Polymorphic Effects](https://arxiv.org/abs/2207.03402), Odersky et al.). Capabilities that can't escape are the [second-class values](https://www.cs.purdue.edu/homes/rompf/papers/osvald-oopsla16.pdf) of Osvald et al. Protocols are typestate: Strom and Yemini, Vault by DeLine and Fähndrich, and the [access permissions](http://www.cs.cmu.edu/~kbierhof/papers/typestate-verification.pdf) of Bierhoff and Aldrich. Logic in the type system and in the language owes a lot to [Flix](https://flix.dev) (Madsen et al.).

The engines: [µKanren](http://webyrd.net/scheme-2013/papers/HemannMuKanren2013.pdf) by Hemann and Friedman, semi-naive Datalog with the round stamps of [egglog](https://arxiv.org/abs/2304.04332), and the provenance of [Soufflé](https://arxiv.org/abs/1907.05045) (Zhao, Subotić and Scholz). Errors as data follow [Total Type Error Localization and Recovery with Holes](https://doi.org/10.1145/3632910) (Zhao et al.). Content hashes are the idea of [Unison](https://www.unison-lang.org), proofs target [Lean 4](https://lean-lang.org/papers/lean4.pdf), and macros as typing come from [Turnstile](https://www2.ccs.neu.edu/racket/pubs/popl17-ckg.pdf).

## Sponsor Development

srs is made with love by [vic](https://github.com/vic). A language with no GC, where memory, state and resources are checked before the program runs, takes a lot of patient work to get right. If srs is useful to you, or you want to see where it goes, please [sponsor vic](https://dendritic.oeiuwq.com/sponsor). Issues and pull requests are welcome.
