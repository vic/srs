# srs

srs is a small language that looks and feels like Scala 3, and it compiles to portable C. The compiler is written in srs itself, in [`./s1`](./s1). A stable [seed](./bootstrap) builds it the first time, using the Zig toolchain.

srs has no garbage collector. Instead, the compiler checks at compile time how your code uses memory, mutable state and other resources. It tracks them as flow effects with handlers. So the C you get has no runtime bookkeeping left in it.


> Why?
>
> I want a better Rust, for me and maybe for you. I have always loved the Scala 3 type system. I have also been exploring [algebraic effects with handlers](https://github.com/denful/fx-rs), especially how to count and order effects. That work applies to linearity and memory management too. [Unison](https://www.unison-lang.org) and [Flix](https://flix.dev) inspired this experiment a lot. I have also worked on [logic programming in Nix](https://github.com/vic/yen), which shows how Datalog can live inside a type system.
>
> I plan to use srs for my new [Nix runtime](https://github.com/denful/dnx). It runs Nix on delta interaction nets, and I want to write it in srs instead of Rust.


See [Where Ideas Come From](#where-the-ideas-come-from).


> What does this mean in practice?
>
> You get a high-level functional language that compiles to any C target. Handlers, effects and type protocols (see below) make resource management much better.
>
> Like Unison and Nix derivations, srs names values and functions by the hash of its content and the hash of its effect requirements. So compiled functions can go into a shared store and be reused. The store keeps the AST apart from the surface syntax, so other syntaxes can sit on top of it, as Unison intended. This suits agentic workflows that run in several workspaces. They can share results instead of rebuilding `./target` and every dependency each time. Unison keeps this store in a DB. srs uses the Nix store approach instead. This also means code can be shipped around to other instances as Unison does for moving code to where data is, and other things like hot-code patching which I inted to use with llvm agents working on srs codebases.
>
> Protocols describe state machines for resources. Memory regions are the main use case. Protocols also fit any other stateful resource, such as a database transaction.
>
> The language compiles to both C and Lean for proving its own kernel.

If you write Scala 3, you already know most of the syntax: `enum`, `match`, `trait`, `given`, and indentation instead of braces. srs adds a type system that tracks two things: where a value lives, and what state a resource is in. The types can also compute things at compile time.

srs is early, and it changes fast. The syntax can still change. The [tests](tests/) show best what works today.

This README starts with what feels familiar. Each section then goes one step further, so you can read it from top to bottom to learn the language.

<details>
<summary>Where we are</summary>

The compiler you can run today is s1. It compiles itself, and everything in this README works with it, except the macros section at the end. s1 was written in a hurry to get the language started. It is imperative inside, with `var` and `while` everywhere, and it stops at the first error.

I am now writing s2, which will replace s1. s2 is written in srs, in a functional style: only `val`, no loops, only recursion. Speed comes first. Its checker is a Datalog program. Protocol states, regions and `var` tracking become facts. Rules derive what holds at each point of a function, and a type error is a fact too.

This gives three things s1 does not have. First, every error is reported, not only the first one. Second, the joins at branches and loops come from the Datalog fixpoint, so nobody writes them by hand. Third, each error can explain *why*, because every derived fact remembers the rule that made it.

The parts s2 stands on live in [s2/](s2): collections, a miniKanren with disequality and finite domains, and a Datalog with stratified negation. They give the same answers as the libraries in [lib/](lib), and they run much faster. I am porting the checker from s1 one part at a time. The order is protocol states first, then regions and vars, then names, purity, the parser, types and generics.

</details>

## Try it

```console
$ nix develop
$ srs-run hello.srs
24
```

`srs-run` compiles your file with the prelude, builds the C and runs it. Here is `hello.srs`:

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

The `handle r = Arena()` line is the one new thing here. Values need a place to live. So you open a region, and the constructors put the nodes in it. We come back to regions soon.

## Pattern matching checks every case

A `match` must cover every case of the enum. Add a new case, and the compiler lists each place that does not handle it yet:

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

A `match` is an expression, so it can go anywhere a value can. It can even be the condition of a loop. `while c match` with `case Nil => false` and `case Cons(_, _) => true` loops until the list is empty. You will see one in the contracts section.

## Generic enums and type aliases

Type parameters go in `[]`, as in Scala 3. Enums can take them too:

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

The compiler finds type arguments from the values you pass, or from the type you expect back. So `val n: Opt[I64] = None` is enough to type `None`. Nesting works too: `Pair(Some(7), false)` is a `Pair[Opt[I64], Bool]`. You can also give the types yourself, as in `id[I64](41)`. Each new type gets its own copy in the C code. Generic code costs nothing at run time. The price is code size and compile time.

Type aliases work as you expect, with or without parameters. They can also use each other:

```scala
type Id [A: Type] = A
type Num = I64
type Maybe [A: Type] = Opt[Id[A]]

val m: Maybe[Num] = Some(1)
```

Mixing types up is a plain type error, such as `type mismatch: Opt[I64] is not Opt[Bool]`.

Examples: [generic](tests/generic.srs), [generic_enum](tests/generic_enum.srs), [typelambda](tests/typelambda.srs), [genum_mismatch](tests/neg/genum_mismatch.srs).

## Traits and givens

Evidence, such as a `Show[A]` instance, goes in `{}`. Evidence always has a name. A `given` can depend on other givens. So `Show[Box[A]]` holds whenever `Show[A]` holds:

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

Then `print(Box(41))` finds the evidence for you and prints `141`. Evidence is found by its type, as in Scala 3. The name lets you pass the evidence yourself. A function that holds `{s: Show[A]}` can call `print{s}(x)`. Local evidence beats a global given. A more specific given beats a general one, as in Scala 3. When two givens are equally good, the compiler does not pick one. It rejects the call as ambiguous. A search for givens can also run forever, so the compiler stops it with `given search ran out of fuel`.

Examples: [traits](tests/traits.srs), [givens](tests/givens.srs), [given_local](tests/given_local.srs), [given_rank](tests/given_rank.srs), [given_ambig](tests/neg/given_ambig.srs), [given_fuel](tests/neg/given_fuel.srs).

## Regions instead of a GC

Now back to regions. A function that builds data says so in its signature, with a `{r: Region}` capability. It uses the same `{}` as evidence, because holding a region counts as evidence too. You do not pass it by hand. The compiler finds the nearest region in scope:

```scala
def build {r: Region} (n: I64): List =
  if n == 0 then Nil else Cons(n, build(n - 1))
```

You can free a region early. A region is a resource with states: open or freed. The protocols section shows how that works. The compiler stops you from using a value after its region is gone:

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

Trying to let a value escape its region, or freeing a region twice, is rejected the same way.

How does this work when values share references? The unit you free is always a whole region, never one object. A region is part of a value's type. So every alias of a value names the same region. Free it, and all the aliases die at once. An escape is a value whose type names a region that has already ended. The region capability itself cannot be aliased. It is second-class: it can be a parameter or the result of a `handle`, but you cannot store it in data, return it, or pass it twice in one call. The trade-off is that you cannot free a single object out of a region.

You can write the region down when you want to be explicit. `^<r>` means "this lives in `r`":

```scala
val q: Opt[I64]^<r> = Some(5)
```

When two regions are in scope, the compiler does not guess which one you mean. You name it at the call with `{}`. This is also where a `var` shows its trick. A `var` has a region as part of its state. When you assign it a value from somewhere else, the region moves with it:

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

Leave out the `{a}` and you get `ambiguous capability, more than one in scope for 'Region'`. The compiler follows a `var` through every branch and around every loop. So a value that moves into a freed region only on the second turn of a loop is still caught. The analysis always finishes. A `var` can only hold regions that are in scope, so after a few turns, going around the loop again adds nothing new. The check is conservative. It rejects what it cannot prove safe, so now and then a correct program is rejected too.

Examples: [region_ok](tests/region_ok.srs), [var_ok](tests/var_ok.srs), [cap_uaf](tests/neg/cap_uaf.srs), [escape](tests/neg/escape.srs), [var_branch](tests/neg/var_branch.srs), [var_loop](tests/neg/var_loop.srs).

## Protocols: resources with states

A `protocol` is a small state machine. It lists the states, where the resource starts and ends, and which ops move it from one state to the next. A `handler` implements the protocol. When you use a resource, the compiler follows its state through your code.

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

If you forget to leave, the compiler tells you that too: `'d' ends its scope in state Open, not an end state`. It also rejects branches that leave a resource in different states. A loop must leave every resource in the state it found it in.

This is typestate, an idea from the 1980s. Vault, and later the access permissions of Bierhoff and Aldrich, showed how to make it work when many names point at one resource. srs keeps it simple by never letting two names share one resource. Typestate fits files, locks and sockets best. [file.lib](tests/file.lib) defines a `File` protocol, and [file_ok](tests/file_ok.srs) uses it. The tests that must fail are [close_no_read](tests/neg/close_no_read.srs) and [branch_state](tests/neg/branch_state.srs).

<details>
<summary>Regions are protocols too: bring your own allocator</summary>

The region from the first example now makes sense. `Region` is a protocol in the prelude. `Arena` and `Heap` are two handlers of it. You can write your own handler, and it works everywhere a region works:

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

Because a region is a protocol, freeing it twice, or allocating after it is freed, is a state error: `op 'free' not allowed in state Freed`. See [double_free](tests/neg/double_free.srs) and [alloc_after_free](tests/neg/alloc_after_free.srs).

</details>

## Facts: functions that know about states

This is the part I enjoy most. A function can state facts in `<>`. Before the call, it lists the facts it needs. After the return type, it lists the facts it leaves behind. Facts can hold variables, so one function can work across many states. Here is a tape you can read twice, and a `readAny` that reads from whatever state the tape is in:

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

The compiler checks the body of `readAny` once for each state it can start from. At each call, it works out where the tape is and moves it one step on. A third `readAny()` fails, because a tape in `Twice` has no read left:

```console
srs:19: error: entry facts do not hold at the call of 'readAny'
```

Examples: [facts_vars](tests/facts_vars.srs), [facts](tests/facts.srs), [fact_entry](tests/neg/fact_entry.srs), [fvar_exit](tests/neg/fvar_exit.srs).

<details>
<summary>Rules: name a path through a protocol</summary>

A protocol can carry its own rules, written as Datalog. Functions can use those rules in their facts. A rule can have several clauses, and it can be recursive. Rules always finish, because the states of a protocol are a fixed set. So there are only so many facts to find. A rule has no inputs or outputs. `twoKnocks(s, s3)` is true for every pair of states that are two knocks apart. `s2` is just a name for the state in the middle.

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

The value is the sum of the two knock results. With a handler whose `knock` returns `3`, that sum is `6`. The facts only say where the door is before and after the calls.

Examples: [rules](tests/rules.srs) (a recursive `reach`), [rule_reach](tests/neg/rule_reach.srs).

</details>

## Signatures are telescopes

You have now met four kinds of brackets in a signature. They all follow one idea. A signature lists everything a function needs, as a row of groups. Each kind of bracket asks for one kind of thing:

- `(x: I64)`: values, as usual.
- `[A: Type]`: types. `A` is the name, and `Type` says what kind of thing it is.
- `{s: Show[A]}`: evidence and capabilities. This is proof that `Show[A]` exists, or a region or a file you hold. Each one has a name.
- `<at(t, Fresh)>`: facts, the states your resources must be in. Facts after the return type are the states you leave them in.

The row reads left to right, like a telescope. Each group can use the names from the groups before it. Here `A` is used by the evidence, the tape `t` is used by the facts, and the values come last:

```scala
def report [A: Type] {s: Show[A]} {t: Tape} <at(t, Fresh)> (x: A): I64 <at(t, Once)> =
  s.show(x) + t.read()

def main(): I64 =
  handle t = MemTape()
  val n = report(35)
  t.stop()
  n
```

At a call, you usually pass only the values. The compiler finds the type, the evidence and the tape for you, and it checks the facts. You can also spell out the groups yourself. As you saw earlier, `report[I64](35)` gives the type, and `build{a}(3)` picks the region by name.

The same groups work on types, which is the next section. A `spec def`, which exists only for proofs, takes no groups at all. An `extern def`, which is a C function, takes all of them. Its telescope is a contract that the compiler trusts.

## Types that carry evidence and facts

The `{}` and `<>` groups work on types too. A `SortedBox[A]` is a plain `Box[A]`. But you can name it only where an `Ord[A]` exists:

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

There is a given for `I64`, but none for `Bool`. So if you ask for a `SortedBox[Bool]`, the compiler answers `no given for Ord[Bool]`.

Facts on a type work the same way. For example, an `OpenFile` can be a plain pointer that you may use only while its file is still open:

```scala
type OpenFile {f: File} <at(f, Opened)> = Ptr
```

Examples: [type_evidence](tests/type_evidence.srs), [type_facts](tests/type_facts.srs).

## Types that compute

Types can match on types. With a `()` group, they can also take plain values that are known at compile time:

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

The value inside `Bits(...)` can also be a call. `Bits(dbl(4))` works when `dbl` is a pure function. A function that prints or allocates cannot go there. The compiler tells you why: `comptime call of a fn with effects: 'noisy'`. Type-level work always ends with an answer. A search that runs out of steps is a compile error, never a "maybe".

To be clear about what that means: a function that computes a type must be pure, and it must also end. srs does not prove that it ends. It runs the function on a step budget. A function that needs more steps than the budget is rejected, even if it would have finished. So the budget stops the compiler from hanging, but it is not a proof. A real termination check is on the list. I am looking at size-change termination for it.

Examples: [typelambda](tests/typelambda.srs), [type_values](tests/type_values.srs), [tval_impure](tests/neg/tval_impure.srs).

## Pure functions run at compile time

The `dbl(4)` above ran while the program compiled. You do not mark a function as pure. A function with no effects in its signature or its body is pure, and the compiler can run it. You can try it yourself with `--eval`. It prints every pure constant:

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

A loop that runs past the step budget, or a division by zero, is a compile error. It is not a hang. For example: `comptime division by zero in 'half'`.

Examples: [eval/basic](tests/eval/basic.srs), [purity](tests/purity.srs), [eval/neg_fuel](tests/eval/neg_fuel.srs).

## A function is its content

Each definition gets a hash of what it *does*, not of what it is called. Local names do not count. A call counts by the hash of the function it calls, not by that function's name. So two functions that differ only in their names get the same hash:

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

This idea comes from Unison. It is the basis for caching compiled code by content. Example: [hash/basic](tests/hash/basic.srs).

## Talking to C

`extern def` declares a C function. It takes the full telescope, so you can describe what the C side does to your resources. The compiler then holds every caller to that description. This example hands out an `OpenFile`, and only while the file is open:

```scala
extern def rt_handle {f: File} <at(f, Opened)> (): OpenFile
```

Generic externs work too. A value of a type parameter is passed to C as a `void*`. So one C symbol serves every type. See [generic](tests/generic.srs) and [type_facts](tests/type_facts.srs).

## Contracts and proofs

`requires`, `ensures`, `invariant` and `decreases` are part of the syntax, together with proof hints. A `spec def` exists only for proofs and specs. It may call only pure functions. The C output contains none of this. s1 can turn these into Lean 4 theorems about its own code. That work is paused until s2 is in place. Treat this section as an early sketch.

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

Specs can also quantify. This one says that after a `push`, a value is in the list exactly when it is the new head, or it was already there:

```scala
def push {r: Region} (h: I64, xs: List): List
  ensures forall v: I64 => memL(v, result) == (h == v || memL(v, xs))
  proof using memL
= Cons(h, xs)
```

</details>

Examples: [contracts](tests/contracts.srs), [spec_impure](tests/neg/spec_impure.srs).

## Logic programming in the box

The last stop is the deep end. The standard libraries include a miniKanren and a Datalog. Both are written in srs, and you can use them in your own programs. srs has no closures. So goals and rules are plain data. You build them, then solve them.

<details>
<summary>miniKanren with constraints</summary>

The library has unification, disequality (`=/=`) and finite domains. This program finds pairs of numbers in `1..3` where the first is smaller:

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

`both`, `in`, `lt` and `two` are one-line helpers that build the goals. Every search runs on fuel. So a goal that would loop forever stops, and the search says so. "Out of fuel" means "no answer within the budget". It does not mean "this never ends". Relations run in both directions. [kanren_search](tests/kanren_search.srs) asks `append` which two lists give `[a, b]`, and it gets all three answers.

More: [kanren](tests/kanren.srs) (unify), [kanren_neq](tests/kanren_neq.srs) (disequality), [kanren_fd](tests/kanren_fd.srs) (finite domains).

</details>

<details>
<summary>Datalog with stratified negation</summary>

```
path(X, Y) :- edge(X, Y).
path(X, Z) :- edge(X, Y), path(Y, Z).
```

Over the edges `a -> b -> c -> d`, this gives:

```console
path(a, b) path(b, c) path(c, d) path(a, c) path(b, d) path(a, d)
```

Negation works as long as it does not loop back on itself. For a cycle, or for a rule with a variable that nothing binds, you get an answer that says so: `negcycle p` or `unsafe p`. Each result also comes with a checker. Give it a forged fact, and it points at the fact: `invalid edge(x, y)`. See [datalog](tests/datalog.srs).

A bare "no" from a logic program is hard to debug. So the s2 Datalog will keep, for every fact, the rule that made it. Then an error can show its proof: which steps put a resource in which state, and where two of them disagree. This idea comes from the provenance feature of Soufflé.

</details>

<details>
<summary>A type checker as a relation</summary>

[turnstile](tests/turnstile.srs) writes a small type checker as one Kanren relation, with one clause per kind of expression. A single run gives back both the type and the expanded code:

```console
cif(cvar(b), cint(1), cint(2)) : I64
ccall(f, cadd(cvar(x), cint(1))) : Bool
reject: ambiguous
```

The language itself is moving in this direction. Type checking and code expansion become one search. The idea comes from Turnstile, [Type Systems as Macros](https://www2.ccs.neu.edu/racket/pubs/popl17-ckg.pdf) by Chang, Knauth and Greenman.

</details>

## Coming next: macros and synthesis

This part is designed, but it is not in the compiler yet. Treat the syntax as a preview.

A macro in srs is not a template, and it does not glue strings together. It is a relation, solved by the same miniKanren you just saw. You write its clauses with the `case` syntax you already know. A call is a goal, and the answer to that goal is the code that replaces the call. A clause can match literals, bind variables, and repeat a variable to require that two arguments are equal. A clause can also add an `if` guard:

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

The compiler works out `n` at compile time. So `unroll(1 + 2, ...)` becomes three prints in a row, with no loop left in the C. If no clause fits, or two clauses fit, the call is an error. A macro that keeps expanding runs out of fuel and stops, like every other compile-time search in srs.

Type checking happens inside that search. It does not run in a second pass afterwards. A clause whose code does not type-check at the call site is a dead end, so the search moves on to the next clause. This is also why errors become plain data inside the compiler. A failed check must be something the search can look at. It must not stop the program.

The same machinery gives three more things that Scala 3 users usually reach for macros or derivation to get:

- **Derivation.** A macro can look at the shape of a type: its cases and their fields. A `json` macro can then write the encoder for your enum. The result is data, a `Json` value built from your cases. It is never a string template.
- **Both directions.** A relation can run both ways, so clauses that encode can often decode too. You write the backward call with a `~`: `json(x)` encodes, and `~json(j)` decodes. Not every macro can run backwards, and decoding can fail. So `~json` gives you an `Option`.
- **Synthesis.** Run the search from a type instead of from a call. miniKanren then looks for a program of that type, built from what is in scope: constructors, matches, your functions and givens. It takes the first answer it finds in a fair search order, so the result is always the same. If it runs out of fuel, it gives up.

Splices come with this too, as a language feature and not only for macros. `fs*` stands for a group of arguments whose count is known at compile time. It expands in place, with no list and no allocation. Each position keeps its own type:

```scala
def area(w: I64, h: I64): I64 = w * h

def f(r: Rect): I64 = r match
  case Rect(fs*) => area(fs*)   // becomes area(w, h)
```

## More examples

Every file in [tests/](tests/) is a program that must compile and run. Its expected output is in the `.out` file next to it. Every file in [tests/neg/](tests/neg/) must be rejected. Its first lines say which error it should give. Read the two folders side by side. Together they make the most complete tour of the language right now.

## Where the ideas come from

srs takes a lot from other people's work, and I want to say so. The surface is [Scala 3](https://docs.scala-lang.org/scala3/). Effects with handlers come from my own [fx-rs](https://github.com/denful/fx-rs). Regions come from Tofte and Talpin's region inference, and from [Cyclone](https://www.cs.umd.edu/projects/cyclone/papers/cyclone-regions.pdf) (Grossman et al.). Regions in types are capture sets, as in Scala 3 capture checking ([Scoped Capabilities for Polymorphic Effects](https://arxiv.org/abs/2207.03402), Odersky et al.). Capabilities that cannot escape are the [second-class values](https://www.cs.purdue.edu/homes/rompf/papers/osvald-oopsla16.pdf) of Osvald et al. Protocols are typestate: Strom and Yemini, Vault by DeLine and Fähndrich, and the [access permissions](http://www.cs.cmu.edu/~kbierhof/papers/typestate-verification.pdf) of Bierhoff and Aldrich. Logic in the type system, and in the language, owes a lot to [Flix](https://flix.dev) (Madsen et al.).

The engines come from several places. [µKanren](http://webyrd.net/scheme-2013/papers/HemannMuKanren2013.pdf) is by Hemann and Friedman. The semi-naive Datalog uses the round stamps of [egglog](https://arxiv.org/abs/2304.04332), and its provenance comes from [Soufflé](https://arxiv.org/abs/1907.05045) (Zhao, Subotić and Scholz). Errors as data follow [Total Type Error Localization and Recovery with Holes](https://doi.org/10.1145/3632910) (Zhao et al.). Content hashes come from [Unison](https://www.unison-lang.org). Proofs target [Lean 4](https://lean-lang.org/papers/lean4.pdf). Macros as typing come from [Turnstile](https://www2.ccs.neu.edu/racket/pubs/popl17-ckg.pdf).

## Sponsor Development

srs is being created by [vic](https://github.com/vic). A language with no GC, where memory, state and resources are checked before the program runs, takes a lot of patient work to get right. If srs is useful to you, or you want to follow where it goes, please [sponsor vic](https://dendritic.oeiuwq.com/sponsor). Issues and pull requests are welcome.
