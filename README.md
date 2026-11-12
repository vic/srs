# srs

[![Sponsor](https://img.shields.io/badge/sponsor-vic-ea4aaa?logo=githubsponsors)](https://github.com/sponsors/vic)

srs is a small language with Scala 3 syntax that compiles to portable C. It has no garbage collector. Instead, the compiler checks at compile time who owns memory, which effects a function uses, and in what order a resource can be used (open, read, close).

The compiler, `s2c`, is written in srs (`s2/`, with the driver in `s2c/main.srs`) and compiles itself: its own C output (`bootstrap/s2c-seed.c`) builds it again, byte for byte. That is how we know a change did not break it.

The tour below starts with plain code and moves toward the parts that make srs different. Every step links the tests that run it, so you can open a real program next to each idea.

## Try it

```console
$ nix develop
$ srs-run hello.srs
24
```

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

That is `hello.srs`. Most of it is what you expect from Scala. The two `handle` lines are the first new idea: `Console` is printing and `Arena` is memory, and `main` says which of them the program gets. We come back to them in [effects](#5-effects-main-decides-what-the-program-may-do) and [regions](#7-memory-without-a-gc-regions).

## The tour

Tests in `tests/s2/prog/` compile, run, and must print their `.out` file. Tests in `tests/s2/neg/` must be rejected with the error code and the line their `// expect:` comments name.

### 1. Enums and `match`

```console
error[not-exhaustive]: the match misses the case 'Cons'
  --> tests/s2/neg/nonexhaustive.srs:4
    |
  4 |   Nil match
    |
    = help: add an arm for it, or a `_` arm
```

A `match` must cover every case. Add a case to an enum and the compiler points at every match that forgot it.

```scala
enum Acc:
  case Acc(sum: I64, count: I64)

def add(s: Acc, x: I64): Acc =
  val Acc(sum, count) = s
  Acc(sum + x, count + 1)
```

`val C(a, b) = e` takes apart an enum with one case, so state can flow through `val`s. Patterns are flat for now: `case W1(x)` binds `x`, and you match what is inside `x` with a second `match`.

Tests: [`neg/nonexhaustive`](tests/s2/neg/nonexhaustive.srs), [`prog/val_pattern`](tests/s2/prog/val_pattern.srs), [`prog/pat_binder`](tests/s2/prog/pat_binder.srs), [`prog/enum_repr`](tests/s2/prog/enum_repr.srs) (258 cases, past a one-byte tag), [`neg/valpat_cases`](tests/s2/neg/valpat_cases.srs), [`neg/pat_nested_unqualified`](tests/s2/neg/pat_nested_unqualified.srs).

### 2. No loops needed: `val`, recursion, tail calls

```scala
def down(n: I64, acc: I64): I64 = if n == 0 then acc else down(n - 1, acc + 1)

// not a tail call: the multiply runs after the call returns
def fact(n: I64): I64 = if n == 0 then 1 else n * fact(n - 1)
```

A call to itself in tail position becomes a C loop, so `down(10000000, 0)` runs in constant stack. It works in the body, in an `if` branch, in a `match` arm and as the last statement of a block. The compiler is written this way: only `val` and recursion.

`var` and `while` are there for code that wants them, and a deep non-tail recursion can ask for a bigger stack with `SRS_STACK=4g`.

Tests: [`prog/tailcall`](tests/s2/prog/tailcall.srs), [`prog/stack_deep`](tests/s2/prog/stack_deep.srs), [`prog/scope_var`](tests/s2/prog/scope_var.srs), [`prog/var_ok`](tests/s2/prog/var_ok.srs).

### 3. Strings and numbers

```scala
val s = "xabcx"
Str.len(s)            // 5
Str.slice(s, 1, 4)    // "abc", clamped to the string
Str.at(s, 9)          // -1
Str.less("ab", "b")   // true, byte order
```

`Str` is a byte string with pure primitives (`len`, `at`, `slice`, `eq`, `less`, `has`). Out of range is a value, not a crash.

```scala
val w: U32 = U32.rotr(305419896, 8) ^ 0xff
val third = F64.div(F64.ofI64(1), F64.ofI64(3))
```

`I64` is the number you compute with. `U32` and `U64` are machine words: they wrap, and only they have bit operations (`& | ^ ~ << >>`). `U8` and `I32` are storage types for bytes and C ints, with no arithmetic. `F64` is a C double with `F64.fmt` and `F64.parse`. Types never mix by accident: `U32 + I64` is `error[mismatch]`, and a literal that does not fit is `error[int-range]`.

Tests: [`prog/str_prims`](tests/s2/prog/str_prims.srs), [`prog/str_less_has`](tests/s2/prog/str_less_has.srs), [`prog/str_words`](tests/s2/prog/str_words.srs), [`prog/bits`](tests/s2/prog/bits.srs), [`prog/bytes`](tests/s2/prog/bytes.srs), [`prog/i32`](tests/s2/prog/i32.srs), [`prog/f64_prims`](tests/s2/prog/f64_prims.srs), [`prog/f64_fmt`](tests/s2/prog/f64_fmt.srs), [`prog/print_i64`](tests/s2/prog/print_i64.srs), [`neg/word_mix`](tests/s2/neg/word_mix.srs), [`neg/word_range`](tests/s2/neg/word_range.srs), [`neg/u8_add`](tests/s2/neg/u8_add.srs).

### 4. Names with dots, and generics

```scala
enum Kanren.Term:
  case Kanren.TVar(n: I64)
  case Kanren.TInt(v: I64)

def Kanren.step(t: Kanren.Term): I64 = t match
  case Kanren.TVar(n) => n
  case Kanren.TInt(v) => v + 100
```

`Kanren.step` is one name: the dot is part of it. That is how modules work for now, so two modules can both have a `Term` or a `step`.

```scala
enum Gen.Opt [A: Type]:
  case Gen.None
  case Gen.Some(v: A)

def Gen.get [A: Type] (o: Gen.Opt[A], d: A): A = o match
  case Gen.None => d
  case Gen.Some(v) => v
```

Type parameters go in `[A: Type]` and types are applied with `[]`, as in Scala 3. Most type arguments are inferred; `id[I64](x)` gives them by hand. Generic code is specialized into plain C, one struct and one function per instance.

Tests: [`prog/modules`](tests/s2/prog/modules.srs), [`prog/generic`](tests/s2/prog/generic.srs), [`prog/generic_enum`](tests/s2/prog/generic_enum.srs), [`prog/check_mode`](tests/s2/prog/check_mode.srs), [`neg/mod_unqualified`](tests/s2/neg/mod_unqualified.srs), [`neg/generic_infer`](tests/s2/neg/generic_infer.srs), [`neg/call_targs`](tests/s2/neg/call_targs.srs).

### 5. Effects: `main` decides what the program may do

```scala
capability Log:
  def say(n: I64): Unit

handler Loud for Log:
  def say(n: I64): Unit =
    Console.print("loud ")
    Console.printI64(n)

def tell(n: I64): Unit = Log.say(n)

def main(): I64 =
  handle io = Srs.Console()
  handle l = Loud()
  tell(1)
  0
```

`tell` asks for `Log.say`, and you never write that it needs `Log`: the compiler works that out from the body (its effect row). Some `handle` around the call has to answer it, and the innermost one wins. A handler's own requests (here `Console.print`) go to the handlers outside it. Pure things like `Str.len` ask for nothing.

```console
error[unhandled-effect]: effect not handled: 'Log'
  --> tests/s2/neg/eff_unhandled.srs:19
    |
 19 |   tell(1)
    |
    = help: open a handler of it in an enclosing block (handle x = H()): main must handle every effect it needs
```

If nobody handles it, that is a compile error, and every place is reported. The `Srs.*` handlers in the prelude are the only code that touches the C runtime (`rt_*`); anywhere else it is `error[rt-outside-srs]`. A handler with no `init` keeps no state and costs nothing.

Tests: [`prog/eff_console`](tests/s2/prog/eff_console.srs), [`prog/eff_inner`](tests/s2/prog/eff_inner.srs), [`prog/eff_row`](tests/s2/prog/eff_row.srs), [`prog/eff_handler_row`](tests/s2/prog/eff_handler_row.srs), [`prog/eff_shadow`](tests/s2/prog/eff_shadow.srs), [`prog/eff_stateless`](tests/s2/prog/eff_stateless.srs), [`prog/cap_nested`](tests/s2/prog/cap_nested.srs), [`neg/eff_unhandled`](tests/s2/neg/eff_unhandled.srs), [`neg/eff_rt`](tests/s2/neg/eff_rt.srs), [`neg/srs_name_forge`](tests/s2/neg/srs_name_forge.srs).

### 6. Traits and givens

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

Evidence goes in `{}` and is found for you with the Scala 3 rules: local evidence first, then the most specific given. Two equally good candidates are an error, never a coin flip, and a search that runs too long is rejected. At a call, `f{a}(x)` picks the evidence by hand.

```scala
trait Ho.Fold [F: Type] [A: Type] [B: Type]:
  def step(acc: B, x: A): B

given Ho.Fold[Ho.Sum, I64, I64]:
  def step(acc: I64, x: I64): I64 = acc + x

def Ho.fold [F: Type] [A: Type] [B: Type] {f: Ho.Fold[F, A, B]} (xs: Ho.List[A], acc: B): B = xs match
  case Ho.Nil => acc
  case Ho.Cons(h, t) => Ho.fold[F, A, B](t, f.step(acc, h))
```

srs has no closures. A function you pass around is a given, named by a marker type (`Ho.Sum` here), so `Ho.fold[Ho.Sum, I64, I64](xs, 0)` sums a list. This is defunctionalization done by the type checker.

Tests: [`prog/traits`](tests/s2/prog/traits.srs), [`prog/givens`](tests/s2/prog/givens.srs), [`prog/given_rank`](tests/s2/prog/given_rank.srs), [`prog/given_local`](tests/s2/prog/given_local.srs), [`prog/given_caps`](tests/s2/prog/given_caps.srs), [`prog/fold`](tests/s2/prog/fold.srs), [`neg/given_ambig`](tests/s2/neg/given_ambig.srs), [`neg/given_none`](tests/s2/neg/given_none.srs), [`neg/given_fuel`](tests/s2/neg/given_fuel.srs), [`neg/trait_miss`](tests/s2/neg/trait_miss.srs), [`neg/chosen_ev`](tests/s2/neg/chosen_ev.srs).

### 7. Memory without a GC: regions

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

Every value lives in a region. `Srs.Arena` is a bump allocator written in srs over `mmap`, and `Srs.Heap` lets you free by hand. You don't pass the region around: the compiler finds the one in scope, and reading a value after its region ended does not compile. A value can't leave the block that ends its region either (`error[region-escape]`).

```scala
def cp {s: Region} {r: Region} (l: List): List<r> = l match
  case Nil => Nil
  case Cons(h, t) => Cons(h, cp{s, r}(t))

def load {o: Region} (): List<o> =
  handle tmp = Srs.Arena()
  val x = build{tmp}(4)
  cp{tmp, o}(x)
```

When two regions are open you name the one you mean. `List<o>` says the result lives in `o` only, so `load` can build in a scratch Arena, copy the answer out, and drop the scratch when the block ends. A game loop does the same with one small Arena per tick, and its memory stays flat.

Tests: [`prog/region_ok`](tests/s2/prog/region_ok.srs), [`prog/copy_region`](tests/s2/prog/copy_region.srs), [`prog/caret`](tests/s2/prog/caret.srs), [`prog/caret_glued`](tests/s2/prog/caret_glued.srs), [`prog/cap_region_two`](tests/s2/prog/cap_region_two.srs), [`prog/arena_reuse`](tests/s2/prog/arena_reuse.srs), [`prog/arena_tick`](tests/s2/prog/arena_tick.srs) (2000 ticks, flat peak memory), [`prog/arena_big`](tests/s2/prog/arena_big.srs), [`prog/pages_gate`](tests/s2/prog/pages_gate.srs), [`neg/use_after_free`](tests/s2/neg/use_after_free.srs), [`neg/escape`](tests/s2/neg/escape.srs), [`neg/caret_bound`](tests/s2/neg/caret_bound.srs), [`neg/cap_ambig`](tests/s2/neg/cap_ambig.srs), [`neg/var_loop`](tests/s2/neg/var_loop.srs), [`neg/tparam_escape`](tests/s2/neg/tparam_escape.srs).

### 8. Arrays and cells

```scala
def Ar.sum(n: I64, xs: Array[I64](n), i: I64, acc: I64): I64 =
  if i >= 0 && i < n then Ar.sum(n, xs, i + 1, acc + xs(i)) else acc
```

`Array[A](n)` carries its length as a value. You index it only where an `if` proves the index is in range, so the C is a plain `p[i]` with no check. Drop the `i >= 0` and it does not compile:

```console
error[index-unproved]: the index is not proved in [0, n) for the array 'xs'
  --> tests/s2/neg/array_unproved.srs:5
    |
  5 |   if i < n then Ar.sum(n, xs, i + 1, acc + xs(i)) else acc
    |
    = help: test it first (if 0 <= i && i < n then xs(i) else ...), or use xs.at(i)
```

`xs.at(j)` is the safe way: it gives you `Array.Ok(v)` or `Array.Out(j)`. Arrays are made full (`Array.fill`, `Array.tabulate`), and `Array.slice` and `Array.blit` need their bounds proved too.

```scala
def Cl.bump(c: Cell[I64]): Unit = Cell.put(c, Cell.get(c) + 1)
```

A `Cell[A]` holds one value you can change. Writing a cell or an array slot is an effect (`Mut`), so `main` needs `handle m = Srs.Mut()` and you can see from a function's row whether it writes.

Tests: [`prog/array`](tests/s2/prog/array.srs), [`prog/array_infer`](tests/s2/prog/array_infer.srs), [`prog/array_put`](tests/s2/prog/array_put.srs), [`prog/array_grow`](tests/s2/prog/array_grow.srs), [`prog/array_rec`](tests/s2/prog/array_rec.srs), [`prog/array_blit`](tests/s2/prog/array_blit.srs), [`prog/cell`](tests/s2/prog/cell.srs), [`prog/cell_data`](tests/s2/prog/cell_data.srs), [`neg/array_unproved`](tests/s2/neg/array_unproved.srs), [`neg/array_slice`](tests/s2/neg/array_slice.srs), [`neg/array_escape`](tests/s2/neg/array_escape.srs), [`neg/array_put_nomut`](tests/s2/neg/array_put_nomut.srs), [`neg/cell_seal_block`](tests/s2/neg/cell_seal_block.srs).

### 9. Capabilities: a resource with an order

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

A `capability` is a state machine: which states exist, where it starts, where it must stop, and which calls move it. Knock at most twice, then leave. Calling `leave` on a shut door is `error[op-not-allowed]`, and forgetting to leave is `error[capability-not-ended]`. A `drop` line names the call that ends it for you at the end of the block.

```scala
def main(): I64 =
  handle r = Srs.Arena()
  r.free()
  r.free()
  0
```

```console
error[op-not-allowed]: op not allowed in this state of the capability 'r'
  --> tests/s2/neg/double_free.srs:6
    |
  6 |   r.free()
    |
    = help: call the ops in the order the capability allows
```

Regions are capabilities too (`Region` in `lib/prelude.srs` has the states `Open` and `Freed`), so a double free is the same kind of error. Capabilities are erased at run time: they cost nothing in the C, and they can't be stored in a value (`error[capability-erased]`).

Tests: [`prog/capability`](tests/s2/prog/capability.srs), [`prog/cap_seq`](tests/s2/prog/cap_seq.srs) (the order `a b{1,2} a c`, as states), [`prog/caps`](tests/s2/prog/caps.srs), [`prog/file_ok`](tests/s2/prog/file_ok.srs), [`neg/double_free`](tests/s2/neg/double_free.srs), [`neg/missing_close`](tests/s2/neg/missing_close.srs), [`neg/branch_state`](tests/s2/neg/branch_state.srs), [`neg/cap_seq_many`](tests/s2/neg/cap_seq_many.srs), [`neg/call_freed`](tests/s2/neg/call_freed.srs), [`neg/erased_field`](tests/s2/neg/erased_field.srs), [`neg/proto_ambiguous`](tests/s2/neg/proto_ambiguous.srs).

### 10. Facts and rules about states

```scala
capability Door:
  ...
  rule def twoKnocks(s, s3) = next(s, knock, s2), next(s2, knock, s3)

def knockTwice {d: Door} <d: s, twoKnocks(s, s3)> (): I64 <d: s3> =
  val a = d.knock()
  a + d.knock()
```

The `<>` groups talk about states. Before the arguments they say what a function needs (`d` is in some state `s` from which two knocks are possible), after the result what it leaves behind (`d` ends in `s3`). A capability can hold Datalog rules, recursive ones too, and the checker solves the states for each call.

A def's binder groups come in this order: `[A: Type]` types, `{s: Show[A]}` evidence and capabilities, `<...>` facts, `(x: A)` values.

Tests: [`prog/rules`](tests/s2/prog/rules.srs), [`prog/facts`](tests/s2/prog/facts.srs), [`prog/facts_vars`](tests/s2/prog/facts_vars.srs), [`neg/fvar_later`](tests/s2/neg/fvar_later.srs), [`neg/fvar_none`](tests/s2/neg/fvar_none.srs), [`neg/rule_reach`](tests/s2/neg/rule_reach.srs), [`neg/rule_safety`](tests/s2/neg/rule_safety.srs), [`neg/fact_unknown`](tests/s2/neg/fact_unknown.srs).

### 11. Handlers that keep state, and handlers that resume

```scala
capability Tick:
  def tick(): I64

handler Cnt for Tick:
  def init(): Cell[I64] = Cell.new(0)
  def tick(self: Cell[I64]): I64 =
    Cell.put(self, Cell.get(self) + 1)
    Cell.get(self)
```

A handler can carry state. `init` makes it when the `handle` runs, in that block's region, and every op gets it as `self`.

```scala
capability NonDet:
  def choose(): Bool

handler All [A: Type] for NonDet:
  def done(x: A): Bag[A] = Leaf(x)
  def choose(k): Bag[A] = Two(resume k(true), resume k(false))

def tree(): Bag[I64] =
  handle nd = All()
  val x = pick()
  val y = pick()
  x * 10 + y
```

A handler can also resume the rest of the block, more than once. Here each `pick` asks `NonDet.choose()`, both answers run, and `tree` collects every outcome: `11 12 21 22`. There are no closures in srs, so the compiler cuts the rest of the block into continuation segments that are plain data.

Tests: [`prog/hstate_count`](tests/s2/prog/hstate_count.srs), [`prog/hstate_self`](tests/s2/prog/hstate_self.srs), [`prog/hstate_array`](tests/s2/prog/hstate_array.srs), [`prog/ms_pick`](tests/s2/prog/ms_pick.srs), [`prog/ms_sum`](tests/s2/prog/ms_sum.srs), [`prog/ms_if`](tests/s2/prog/ms_if.srs), [`prog/ms_state_trip`](tests/s2/prog/ms_state_trip.srs), [`neg/ms_resume_not_k`](tests/s2/neg/ms_resume_not_k.srs), [`neg/ms_state_two`](tests/s2/neg/ms_state_two.srs), [`neg/hstate_shape`](tests/s2/neg/hstate_shape.srs), [`tests/c/multishot`](tests/c/multishot) (the C prototypes this started from).

### 12. The outside world

```scala
def main(): I64 =
  handle io = Srs.Console()
  handle r = Srs.Arena()
  handle fs = Srs.Files()
  val res = Files.readAll("tests/s2/fs/a.txt")
  res match
    case Os.Ok(s) => Console.print(s)
    case Os.Fail(e) => Console.print("fail\n")
  0
```

Files, the environment, the clock, Unix sockets and child processes are capabilities: `Files`, `Env`, `Clock`, `Net`, `Process`. A failure is a value (`Os.NotFound`, `Os.Denied`, ...) and never aborts the program. `Net` has states, so sending on a closed socket does not compile.

```console
error[ambient-world]: a world capability is handled only in main, or in a def that already holds it: 'Env'
  --> tests/s2/neg/ambient_env.srs:6
    |
  6 |   handle e = Srs.Env()
    |
    = help: handle it in main and pass it down: a def that needs it takes it as a {} binder
```

Only `main` may open these handlers, so a library can't reach the world behind your back. A function that needs one says so with a binder like `{_: Env}`.

Tests: [`prog/os_files`](tests/s2/prog/os_files.srs), [`prog/os_env`](tests/s2/prog/os_env.srs), [`prog/os_clock`](tests/s2/prog/os_clock.srs), [`prog/os_net`](tests/s2/prog/os_net.srs), [`prog/os_proc`](tests/s2/prog/os_proc.srs), [`prog/ambient_env_ok`](tests/s2/prog/ambient_env_ok.srs), [`neg/ambient_env`](tests/s2/neg/ambient_env.srs), [`neg/ambient_files`](tests/s2/neg/ambient_files.srs), [`neg/net_after_close`](tests/s2/neg/net_after_close.srs), [`neg/os_rt_outside`](tests/s2/neg/os_rt_outside.srs).

### 13. Calling C

```scala
extern "libc" val O_RDONLY: I32

extern "libc" struct flock:
  l_start: I64
  l_len: I64
  l_pid: I32

def Cs.size(s: flock): I64 = s.l_start()
```

C comes in through `extern "libc"`: a function declared against the real libc headers, a constant or macro as a value, a struct whose fields are read through the real header. The C compiler checks each one against the header, so a wrong type does not build. `flock.new()` makes a zeroed struct in the current region.

A call to a libc function is legal only inside a `Srs.*` handler (`error[libc-outside-handler]`), so the unsafe part stays in a few small places. `CStr` is a `const char*` you can store and pass, nothing more.

Tests: [`prog/libc_val`](tests/s2/prog/libc_val.srs), [`prog/cstruct_new`](tests/s2/prog/cstruct_new.srs), [`prog/cstr_type`](tests/s2/prog/cstr_type.srs), [`prog/cap_alloc`](tests/s2/prog/cap_alloc.srs), [`cok/`](tests/s2/cok) (C that must build), [`cneg/`](tests/s2/cneg) (C the compiler must refuse), [`neg/libc_outside`](tests/s2/neg/libc_outside.srs), [`neg/cstr_add`](tests/s2/neg/cstr_add.srs).

### 14. Types that compute

```scala
type Id [A: Type] = A
type Wide [A: Type] = A match
  case Bool => I64
  case I64 => I64

type Bits (n: I64) = n match
  case 8 => Bool
  case _ => I64

def tb1(x: Bits(8)): Bool = x
def tb3(x: Bits(dbl(4))): Bool = !x
```

A type can be an alias, a match on types, or a match on values that runs at compile time (`dbl(4)` is a pure function call). The type level is pure and always ends: when its step budget runs out, that is a rejection, never "don't know".

```scala
type SortedBox [A: Type] {o: Ord[A]} = Box[A]
type OpenFile {f: File} <f: Opened> = Ptr
```

A type can also ask for evidence or a state. `SortedBox[A]` can only be named where `Ord[A]` is known, and an `OpenFile` can only be read while its `File` is `Opened`.

Tests: [`prog/typelambda`](tests/s2/prog/typelambda.srs), [`prog/type_values`](tests/s2/prog/type_values.srs), [`prog/type_evidence`](tests/s2/prog/type_evidence.srs), [`prog/type_facts`](tests/s2/prog/type_facts.srs), [`prog/tf_epoch`](tests/s2/prog/tf_epoch.srs), [`neg/tl_fuel`](tests/s2/neg/tl_fuel.srs), [`neg/tl_nocase`](tests/s2/neg/tl_nocase.srs), [`neg/tval_runtime`](tests/s2/neg/tval_runtime.srs), [`neg/tev_none`](tests/s2/neg/tev_none.srs), [`neg/tf_stale`](tests/s2/neg/tf_stale.srs).

### 15. Values computed at compile time

```scala
def isEven(n: I64): Bool = if n == 0 then true else isOdd(n - 1)
def isOdd(n: I64): Bool = if n == 0 then false else isEven(n - 1)
val sqEven: Bool = isEven(sq(3))
```

```console
$ s2c --eval lib/prelude.srs tests/s2/eval/basic.srs
ce1 9
ce2 true
ce3 6
ce4 3
ce5 ECons(1, ECons(2, ENil))
```

A top-level `val x: T = e` is computed by the compiler, and `s2c --eval` prints each one. Its body may call only pure functions: the compiler infers which functions are pure, so you never mark them. A call that prints is `error[impure-call]`, and a loop that never ends runs out of steps and is rejected.

Tests: [`prog/purity`](tests/s2/prog/purity.srs), [`eval/basic`](tests/s2/eval/basic.srs), [`eval/str`](tests/s2/eval/str.srs), [`eval/neg_fuel`](tests/s2/eval/neg_fuel.srs), [`neg/cval_impure`](tests/s2/neg/cval_impure.srs), [`neg/pure_mutual`](tests/s2/neg/pure_mutual.srs), [`neg/val_runtime`](tests/s2/neg/val_runtime.srs).

### 16. Contracts

```scala
def count(xs: List): I64
  requires size(xs) >= 0
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
    ...
```

`requires`, `ensures`, `invariant`, `decreases`, `forall` and `proof` clauses parse, are checked, and are erased in the C. Proving them in Lean 4 waits until the core of the language stops moving.

Tests: [`prog/contracts`](tests/s2/prog/contracts.srs).

### 17. Logic engines, in srs

```console
$ srs-run lib/kanren.srs tests/s2/prog/turnstile.srs
cint(1) : I64
cif(cvar(b), cint(1), cint(2)) : I64
...
```

miniKanren (unification, disequality `=/=`, finite domains, a fair search with a step budget) and Datalog (semi-naive, indexed, stratified negation, a proof for every derived fact) are libraries written in srs. `prog/turnstile` is a small type checker written as a Kanren relation. The compiler checks itself with its own Datalog engine: names, effect rows, capability states and the memory report are all Datalog programs.

Tests: [`prog/kanren`](tests/s2/prog/kanren.srs), [`prog/kanren_search`](tests/s2/prog/kanren_search.srs), [`prog/kanren_neq`](tests/s2/prog/kanren_neq.srs), [`prog/kanren_fd`](tests/s2/prog/kanren_fd.srs), [`prog/datalog`](tests/s2/prog/datalog.srs), [`prog/turnstile`](tests/s2/prog/turnstile.srs), and the compiler's own engines: [`datalog`](tests/s2/datalog.srs), [`dprov`](tests/s2/dprov.srs) (the proof of each fact), [`kanren`](tests/s2/kanren.srs), [`ksearch`](tests/s2/ksearch.srs), [`kfd`](tests/s2/kfd.srs), [`flow`](tests/s2/flow.srs).

### 18. Names are hashes

```console
$ s2c --hash lib/prelude.srs tests/s2/hash/golden.srs
...
k 240345295193635661.-2832193521730186299.-4785298233460066510.7926300676138384823
```

`s2c --hash` names each declaration by the BLAKE3 hash of its syntax tree, not by what you called it. Rename the arguments and the hash stays the same; change the body and it moves. `s2c --store-check` writes declarations into a content-addressed store (`SRS_STORE`, default `$HOME/.srs/store`), the way Nix and Unison do. A store entry is written through a capability with states, so a write that is never committed does not compile.

Tests: [`hash/basic`](tests/s2/hash/basic.srs), [`hash/valpat`](tests/s2/hash/valpat.srs), [`hash/golden`](tests/s2/hash/golden.srs), [`b3`](tests/s2/b3.srs) (the official BLAKE3 vectors).

### 19. What the compiler knows about your memory

```console
$ s2c --mem lib/prelude.srs tests/s2/mem/once.srs
{"regions":[{"id":0,"def":"main","var":"r","handler":"Srs.Arena", ...
```

`s2c --mem` prints what the memory analysis found, as one JSON object: each region and what fills it, each allocation site (its bytes, whether it dies in its function or escapes), each variable's moves, and where a box can be rebuilt in place. The analysis is a Datalog program, and the gate audits the compiler's report on itself.

The default C already uses it. Only the functions `main` and its handlers reach are emitted. A case with one boxed field is that pointer, with no box around it. A function that runs once and makes many boxes runs in a scratch Arena that is freed after its result is copied out (it cut the compiler's own peak memory by 47%). `--mem-reuse` also rebuilds a box in place when nothing else holds it, and `--no-mem-optimization` gives the plain C.

Tests: [`tests/s2/mem/`](tests/s2/mem) (`once`, `many`, `death`, `frees`, `moves`, `reuse`, `compact`, ...), [`prog/scratch`](tests/s2/prog/scratch.srs), [`prog/reuse_run`](tests/s2/prog/reuse_run.srs), [`prog/tagless`](tests/s2/prog/tagless.srs).

## Errors

```console
error[mismatch]: the value has the wrong type
  --> tests/s2/neg/mismatch.srs:4
    |
  4 |   val x: I64 = true
    |
    = expected: I64
    = found:    Bool
    = help: give a value of the expected type, or change the declared type
```

Errors look like Rust's: a code, the file and line, the source line, what was expected and what was found when types differ, and a help line. A phase returns its errors as data, and every error is printed, not only the first. The compiler never exits in the middle of a check.

<details>
<summary>Every error code, with a test that triggers it</summary>

* **Regions**: [`use-after-free`](tests/s2/neg/use_after_free.srs), [`region-escape`](tests/s2/neg/escape.srs), [`capability-bound`](tests/s2/neg/caret_bound.srs), [`no-capability`](tests/s2/neg/cap_none.srs), [`cell-seal`](tests/s2/neg/cell_seal_block.srs), [`put-data`](tests/s2/neg/array_put_data.srs)
* **Capabilities**: [`op-not-allowed`](tests/s2/neg/double_free.srs), [`capability-not-ended`](tests/s2/neg/missing_close.srs), [`branch-states`](tests/s2/neg/branch_state.srs), [`exit-state`](tests/s2/neg/sig_state.srs), [`protocol-ambiguous`](tests/s2/neg/proto_ambiguous.srs), [`stale-value`](tests/s2/neg/tf_stale.srs), [`capability-erased`](tests/s2/neg/erased_field.srs), [`capability-value`](tests/s2/neg/cap_value.srs), [`capability-param`](tests/s2/neg/cap_param.srs)
* **Facts and rules**: [`fact-not-capability`](tests/s2/neg/fact_notcap.srs), [`fact-not-op`](tests/s2/neg/fvar_op.srs), [`fact-unbound`](tests/s2/neg/fvar_unbound.srs), [`fact-twice`](tests/s2/neg/fact_twice.srs), [`unknown-state`](tests/s2/neg/fact_state.srs), [`unknown-relation`](tests/s2/neg/fact_unknown.srs), [`entry-facts-unsolvable`](tests/s2/neg/fvar_none.srs), [`rule-unsafe`](tests/s2/neg/rule_safety.srs), [`rule-unknown`](tests/s2/neg/rule_unknown.srs), [`rule-arity`](tests/s2/neg/rule_clauses.srs), [`relation-arity`](tests/s2/neg/rule_arity.srs), [`rule-op`](tests/s2/neg/rule_op.srs), [`reserved-relation`](tests/s2/neg/rule_reserved.srs)
* **Effects and handlers**: [`unhandled-effect`](tests/s2/neg/eff_unhandled.srs), [`rt-outside-srs`](tests/s2/neg/eff_rt.srs), [`ambient-world`](tests/s2/neg/ambient_env.srs), [`reserved-name`](tests/s2/neg/srs_name_forge.srs), [`not-a-capability`](tests/s2/neg/handler_trait.srs), [`handler-state-shape`](tests/s2/neg/hstate_shape.srs), [`handler-state-type`](tests/s2/neg/hstate_mixed.srs), [`op-signature`](tests/s2/neg/op_region_sig.srs), [`op-binder`](tests/s2/neg/op_binder_type.srs), [`op-result-choice`](tests/s2/neg/op_result_choice.srs), [`op-result-capability`](tests/s2/neg/op_result_cap.srs), [`answer-type`](tests/s2/neg/ms_answer.srs), [`resume-not-k`](tests/s2/neg/ms_resume_not_k.srs), [`multishot-shape`](tests/s2/neg/ms_shape_nested.srs), [`multishot-state`](tests/s2/neg/ms_state_two.srs)
* **Givens and evidence**: [`ambiguous-givens`](tests/s2/neg/given_ambig.srs), [`no-given`](tests/s2/neg/given_none.srs), [`given-fuel`](tests/s2/neg/given_fuel.srs), [`given-row`](tests/s2/neg/given_row.srs), [`not-a-trait`](tests/s2/neg/given_cap.srs), [`binder-not-in-head`](tests/s2/neg/given_head.srs), [`ambiguous-evidence`](tests/s2/neg/ev_ambig_local.srs), [`evidence-value`](tests/s2/neg/ev_value.srs), [`chosen-count`](tests/s2/neg/chosen_count.srs), [`chosen-evidence`](tests/s2/neg/chosen_ev.srs), [`chosen-not-capability`](tests/s2/neg/chosen_notcap.srs), [`not-a-method`](tests/s2/neg/trait_extra.srs), [`missing-method`](tests/s2/neg/trait_miss.srs), [`method-signature`](tests/s2/neg/trait_sig.srs), [`trait-arity`](tests/s2/neg/trait_arity.srs), [`no-op`](tests/s2/neg/ev_method.srs)
* **Types**: [`mismatch`](tests/s2/neg/mismatch.srs), [`cannot-infer`](tests/s2/neg/generic_infer.srs), [`binder-hides-type`](tests/s2/neg/generic_hide.srs), [`extern-slot`](tests/s2/neg/generic_ptr.srs), [`arity`](tests/s2/neg/call_targs.srs), [`not-exhaustive`](tests/s2/neg/nonexhaustive.srs), [`nested-pattern`](tests/s2/neg/pat_nested_unqualified.srs), [`pattern-arity`](tests/s2/neg/valpat_arity.srs), [`int-range`](tests/s2/neg/word_range.srs)
* **Arrays**: [`index-unproved`](tests/s2/neg/array_unproved.srs), [`slice-unproved`](tests/s2/neg/array_slice.srs), [`length-unnamed`](tests/s2/neg/array_loop.srs), [`assign-val`](tests/s2/neg/array_assign.srs)
* **Type level and compile time**: [`type-fuel`](tests/s2/neg/tl_fuel.srs), [`type-arity`](tests/s2/neg/tl_arity.srs), [`no-type-case`](tests/s2/neg/tl_nocase.srs), [`value-args`](tests/s2/neg/tval_none.srs), [`value-arg-type`](tests/s2/neg/tval_argtype.srs), [`value-pattern-type`](tests/s2/neg/tval_pattern.srs), [`value-binder-type`](tests/s2/neg/tval_binder.srs), [`no-compile-time-value`](tests/s2/neg/tval_fuel.srs), [`impure-call`](tests/s2/neg/cval_impure.srs), [`comptime-handle`](tests/s2/neg/cval_handle.srs), [`val-at-run-time`](tests/s2/neg/val_runtime.srs), [`comptime-no-value`](tests/s2/eval/neg_word.srs)
* **C**: [`libc-outside-handler`](tests/s2/neg/libc_outside.srs), [`c-fragment`](tests/s2/frag/exit.srs)
* **Names and syntax**: [`duplicate`](tests/s2/neg/dup_def.srs), [`unknown-name`](tests/s2/neg/mod_unknown.srs), [`unknown-type`](tests/s2/neg/trait_unknown.srs), [`parse`](tests/s2/neg/spec_gone.srs)

</details>

## Formatting

```console
$ s2c fmt --check lib/*.srs s2/*.srs s2c/main.srs
$ s2c fmt lib/*.srs s2/*.srs s2c/main.srs
```

`s2c fmt` compiles srs to srs: Scala 3 layout at 120 columns, comments kept with the code they describe. It also removes declarations that nothing reaches from a `main`, a top-level `val` or a `// format: off` region. `--check` lists the files that would change and exits 1. The whole repo is formatted, and the gate checks it ([`fmt/dead`](tests/s2/fmt/dead.srs)).

## Working on srs

```console
$ srs-build           # build s2c from the seed to $B/srs
$ srs-test            # the gate: seed -> s2c -> s2c again (same C), then every test
$ srs-bench           # speed: fails when slower than bench/baseline.txt
```

How to bootstrap, test, verify and send a change is in [CONTRIBUTING.md](CONTRIBUTING.md). Every change that lands is in the [CHANGELOG](CHANGELOG.md), newest first.

`s0` and `s1` (the first two compilers) are history. They stay in the tree, and nothing builds or runs them.

## Coming next

* The rough edges of s2 come first. They are tracked and fixed before s3.
* **s3**: relational macros written as patterns and evaluated at compile time, type-directed encoders and decoders, and synthesis from a signature.
* **Lean 4**: proofs of the kernel rules, once the core is stable.

## What srs learns from

srs takes ideas from many papers and projects. None of them is copied: each one gave us a rule, a shape or a warning, and the notes behind each design say which.

<details>
<summary>Syntax, types and errors</summary>

* [Scala 3](https://docs.scala-lang.org/scala3/): the surface syntax, traits, givens and their ranking, binder groups.
* [Scoped Capabilities for Polymorphic Effects](https://arxiv.org/abs/2207.03402) (*Odersky et al., 2022*): capture sets, the region list `T<r>` on a type.
* *Capturing Types* (*Boruch-Gruszecki et al., TOPLAS 2023*): capture sets for capabilities.
* [A Gentle Introduction to Second-Class Values](https://www.cs.purdue.edu/homes/rompf/papers/osvald-oopsla16.pdf) (*Osvald et al., OOPSLA 2016*): capabilities that are never returned or stored.
* *Effekt* capability passing (*Brachthäuser et al., OOPSLA 2020*): `{}` binders as second-class capabilities.
* [Type Systems as Macros](https://www2.ccs.neu.edu/racket/pubs/popl17-ckg.pdf) (*Chang, Knauth & Greenman, POPL 2017*) and *Turnstile+* (*Chang et al., POPL 2020*): checking and rewriting in one pass.
* [Total Type Error Localization and Recovery with Holes](https://doi.org/10.1145/3632910) (*Zhao et al., POPL 2024*): every error reported, the program rejected if there is one.
* *Statically Contextualizing Large Language Models with Typed Holes* (*2024*): typed holes as input to a repair loop.
* *Knowing When to Ask* (*Rouvoet et al., 2020*, Statix): the order in which name queries are safe to answer.
* *SHErrLoc* (*2014*): an unsolvable constraint path as the error explanation.
* *Tabled Typeclass Resolution* (*Selsam et al., 2020*): why given search keeps a step budget.
* *Liquid Types* (*Rondon et al., PLDI 2008*): facts from branch conditions, used for array indexes.
* *Eliminating Array Bound Checking Through Dependent Types* (*Xi & Pfenning, PLDI 1998*): an index typed by its array needs no run-time check.
* *Fin* as an index type (*McBride & McKinna, 2004*) and *Parse, Don't Validate* (*King, 2019*): data that can't be built wrong.
* [A Typed, Algebraic Approach to Parsing](https://www.cl.cam.ac.uk/~nk480/parsing.pdf) (*Krishnaswami & Yallop, PLDI 2019*): grammars that never backtrack.
* *I Got Plenty o' Nuttin'* (*McBride, 2016*): quantities on binders.
* [Everybody's Got To Be Somewhere](https://arxiv.org/abs/1807.04085) (*McBride, 2018*): scope as part of the term.
* *Size-Change Termination* (*Lee, Jones & Ben-Amram, POPL 2001*): checking `decreases`.
* Dataflow fixpoints (*Kildall, 1973*; *Cousot & Cousot, 1977*): a checker that is sound and always ends.
* Lenses (*Foster et al., TOPLAS 2007*) and invertible syntax (*Rendel & Ostermann, 2010*): a printer that gives back what the parser read.
* *Defunctionalization* (*Reynolds, 1972*): functions as givens named by a marker type.

</details>

<details>
<summary>Memory, regions and ownership</summary>

* [Region-Based Memory Management](http://web.cs.ucla.edu/~palsberg/tba/papers/tofte-talpin-iandc97.pdf) (*Tofte & Talpin, 1997*): regions, their inference, the escape rule.
* *From Region Inference to von Neumann Machines via Region Representation Inference* (*Birkedal, Tofte & Vejlstrup, POPL 1996*) and *A Retrospective on Region-Based Memory Management* (*Tofte et al., HOSC 2004*): finite and unbounded regions.
* *Parallelism in a Region Inference Context* (*Elsman & Henriksen, PLDI 2023*): region pages and free lists.
* [Region-Based Memory Management in Cyclone](https://www.cs.umd.edu/projects/cyclone/papers/cyclone-regions.pdf) (*Grossman et al., PLDI 2002*): explicit regions, outlives bounds, safe manual free.
* [Polymorphic Reachability Types](https://arxiv.org/abs/2307.13844) (*Wei et al., POPL 2024*): a call's result lives in its arguments' regions.
* [Capture Now, Consume Later](https://arxiv.org/abs/2510.08939) (*Deng et al.*): a free is a kill, and a use after it is rejected.
* [When Lifetimes Liberate](https://arxiv.org/abs/2509.04253) (*He et al.*): arenas and scoped escape.
* [Spegion](https://arxiv.org/abs/2506.02182) (*Hughes, Vollmer & Batty, 2025*): regions through an effect system.
* [Yarrow](https://arxiv.org/abs/2607.15876) (*Mathiasen & Timany*): effect handlers and regions together, and why multi-shot is hard.
* [Cambria](https://arxiv.org/abs/2608.27798) (*Liell-Cock & Staton*): allocation as an effect that is erased at run time.
* *Static Prediction of Heap Space Usage* (*Hofmann & Jost, POPL 2003*): heap bounds.
* *Perceus* (*Reinking, Xie, de Moura & Leijen, PLDI 2021*), *FP²* (*Lorenzen, Leijen & Swierstra, ICFP 2023*) and *Counting Immutable Beans* (*IFL 2019*): rebuilding a box in place when nothing else holds it.
* Cheney's copying collector (*1970*): copying a result out of a scratch region.
* *Tree Borrows* (*PLDI 2025*), *Stacked Borrows* (*POPL 2020*), *RustBelt* (*Jung et al., POPL 2018*), *DRFcaml* (*2025*): aliasing and race freedom in Rust and OCaml.
* Persistent data: path copying (*Driscoll et al., 1989*; *Okasaki, 1998*), Okasaki's queue, weight-balanced trees (*Adams, JFP 1993*; *Hirai & Yamamoto, JFP 2011*), [Just Join for Parallel Ordered Sets](https://arxiv.org/abs/1602.02120) (*Blelloch, Ferizović & Sun, SPAA 2016*), 2-3-4 trees (*Guibas & Sedgewick, 1978*), and the ones we measured and passed on for now: integer maps (*Okasaki & Gill, 1998*), HAMT (*Bagwell, 2001*), CHAMP (*Steindorfer & Vinju, OOPSLA 2015*), RRB vectors (*Stucki et al., ICFP 2015*), finger trees (*Hinze & Paterson, JFP 2006*), hash-consing (*Filliâtre & Conchon, 2006*).

</details>

<details>
<summary>Typestate, protocols and effects</summary>

* [Typestate](https://doi.org/10.1109/TSE.1986.6312929) (*Strom & Yemini, 1986*): checks that depend on a resource's state.
* [Enforcing High-Level Protocols in Low-Level Software](https://doi.org/10.1145/378795.378811) (*DeLine & Fähndrich, PLDI 2001*): Vault, states tracked by key; and *Adoption and Focus* (*Fähndrich & DeLine, PLDI 2002*).
* [Modular Typestate Checking of Aliased Objects](http://www.cs.cmu.edu/~kbierhof/papers/typestate-verification.pdf) (*Bierhoff & Aldrich, OOPSLA 2007*): access permissions.
* *Type-Based Temporal Resource Usage Analysis* (*Cao & Sekiyama, POPL 2026*) and *Resource Usage Analysis* (*Igarashi & Kobayashi, POPL 2002*): protocols as properties of traces.
* *History Effects and Verification* (*Skalka & Smith, APLAS 2004*): effects as event histories.
* *Visibly Pushdown Languages* (*Alur & Madhusudan, STOC 2004*) and [Shuffle of Visibly Pushdown Languages](https://arxiv.org/abs/2504.10800) (*Cheng & Farzan*): which protocols stay decidable.
* *Effects as Sessions, Sessions as Effects* (*Orchard & Yoshida, POPL 2016*): a capability and a session are the same object.
* Flow typing with a context before and after each expression (*Wilshaw & Hutton*).
* [fx-rs](https://github.com/denful/fx-rs): the effect kernel and its laws.
* kyo: effect rows, the innermost handler, a program runs when its row is empty.
* Koka (*Leijen, POPL 2017*), *Effect Handlers, Evidently* (*Xie et al., ICFP 2020*: handlers that resume at the tail are direct calls), *Generalized Evidence Passing for Effect Handlers* (*Xie & Leijen, ICFP 2021*), *Boolean Unification of Effects* and *Purity Reflection* (*Madsen, 2020 and 2023*).
* *Robust Composition* (*Miller, 2006*): least authority and no ambient capabilities, the reason only `main` touches the world.
* [Keel](https://arxiv.org/abs/2611.11117) (*Cai, Chang & Nagarakatte*): a small checked C fragment and static handlers.

</details>

<details>
<summary>Logic engines</summary>

* [microKanren](http://webyrd.net/scheme-2013/papers/HemannMuKanren2013.pdf) (*Hemann & Friedman, 2013*): the relational core, goals as data.
* [Certified Semantics for Relational Programming](https://arxiv.org/abs/2005.01018) (*Rozplokhas, Vyatkin & Boulytchev, APLAS 2020*) and *Certified Semantics for Disequality* (*Rozplokhas & Boulytchev*): a fair search with fuel, and what a complete answer means.
* Fast Kanren: triangular substitutions (*Byrd, 2009*), structure sharing (*Boyer & Moore, 1972*), first-argument indexing (*Warren, 1983*), SLG tabling (*Chen & Warren, 1996*), bottom-up tabling (*Kudasov, 2026*), typed miniKanren (*Kosarev & Boulytchev*), interleaving search cost (*Rozplokhas & Boulytchev, FLOPS 2022*), persistent union-find (*Conchon & Filliâtre, 2007*), AC-3 constraint settling (*Mackworth, 1977*; *Apt, 1999*).
* [Flix](https://flix.dev) (*Madsen et al.*): Datalog inside a functional language, pure heads and guards.
* [Better Together: Unification-based Equality Saturation in Egglog](https://arxiv.org/abs/2304.04332) (*Zhang et al., 2023*): semi-naive Datalog by round stamps.
* [Provenancing Datalog Execution in Soufflé](https://arxiv.org/abs/1907.05045) (*Zhao, Subotić & Scholz*): a proof for each derived fact.
* *Provenance Semirings* (*Green et al., 2007*), *Stratified Datalog* (*Apt, Blair & Walker, 1988*), *Dedalus* (*Alvaro et al., 2010*), stratification of first-class Datalog (*Starup, 2023*).
* Integrity constraints (*Nicolas, 1982*): `not (...)` clauses that deny a state.
* Fast Datalog: Soufflé's specialized B-tree (*Jordan et al., PPoPP 2019*), Brie (*Jordan et al., 2019*), automatic index selection (*Subotić et al., VLDB 2018*), program synthesis (*Jordan, Scholz & Subotić, CAV 2016*; *Scholz et al., CC 2016*), egg (*Willsey et al., POPL 2021*), relational e-matching (*Zhang et al., POPL 2022*), worst-case optimal joins (*Ngo, Ré & Rudra, 2013*; *Veldhuizen, ICDT 2014*), *Free Join* (*Wang, Willsey & Suciu, SIGMOD 2023*), Ascent and *BYODS* (*Sahebolamri et al., CC 2022 and OOPSLA 2023*), RecStep (*Fan et al., VLDB 2019*), COST (*McSherry et al., HotOS 2015*).
* Incremental Datalog: *DBSP* (*Budiu, McSherry et al., VLDB 2023*), *Differential Dataflow* (*McSherry et al., CIDR 2013*), shared arrangements (*McSherry et al., VLDB 2020*), [FlowLog](https://arxiv.org/abs/2511.00865).
* Generalized Dijkstra (*Knuth, 1977*), congruence closure (*Nelson & Oppen, 1980*), strongly connected components (*Tarjan, 1972*), CFL reachability (*Reps, 1998*).
* Analyses as Datalog: Polonius, Doop, Chord (*Naik, Aiken & Whaley, PLDI 2006*), lock-order deadlocks (*Naik et al., ICSE 2009*), RacerX (*Engler & Ashcraft, SOSP 2003*).

</details>

<details>
<summary>Hashing, builds and proofs</summary>

* [Unison](https://www.unison-lang.org): content-addressed code, names as metadata.
* Nix: a store keyed by the hash of what built it.
* *BLAKE3* (*O'Connor, Aumasson, Neves & Wilcox-O'Hearn, 2020*): the store digest.
* *Hashing Modulo Alpha-Equivalence* (*Maziarz et al., PLDI 2021*), ordered-graph isomorphism (*Jiang & Bunke, 1999*), colour refinement (*Berkholz, Bonsma & Grohe, 2017*).
* *Build Systems à la Carte* (*Mokhov, Mitchell & Peyton Jones, ICFP 2018*), *Adapton* (*Hammer et al., PLDI 2014*), Salsa: early cutoff and incremental work.
* *Partial Evaluation and Automatic Program Generation* (*Jones, Gomard & Sestoft, 1993*): what can run at compile time.
* [Encodability and Separation for a Reflective Higher-Order Calculus](https://arxiv.org/abs/2209.02356) (*Lybech, 2022*) and the ρ-calculus (*Meredith & Radestock, 2005*): names as digests.
* [The Lean 4 Theorem Prover and Programming Language](https://lean-lang.org/papers/lean4.pdf) (*de Moura & Ullrich, 2021*), weakest preconditions (*Dijkstra, 1975*), Boogie (*Leino, 2005*): the proof backend.

</details>

<details>
<summary>Read for what comes next: concurrency and durable programs</summary>

* Processes and channels: the π-calculus (*Milner, Parrow & Walker, 1992*), CSP (*Hoare, 1978*), the join calculus (*Fournet & Gonthier, POPL 1996*), actors (*Hewitt et al., 1973*; *Agha, 1986*), Kahn networks (*1974*).
* Sessions: *Types for Dyadic Interaction* (*Honda, 1993*), multiparty session types (*Honda, Yoshida & Carbone, POPL 2008*), deadlock freedom by design (*Carbone & Montesi, POPL 2013*), sessions as logic (*Caires & Pfenning, 2010*; *Wadler, 2012*), cyclic sessions (*Kobayashi, 2006*).
* Ownership across threads: concurrent separation logic (*O'Hearn*; *Brookes*, 2004), fractional permissions (*Boyland, 2003*), Pony deny capabilities (*Clebsch et al., 2015*), [Behaviour-Oriented Concurrency](https://arxiv.org/abs/2309.02983) (*Cheeseman et al., OOPSLA 2023*, Verona), DPJ (*Bocchino et al., OOPSLA 2009*).
* Determinism: CALM (*Ameloot et al.*; *Hellerstein & Alvaro*; *Interlandi & Tanca*), Bloom^L (*Conway et al., 2012*), LVars (*Kuper & Newton, 2013*), the Par monad (*Marlow et al., 2011*), CRDTs (*Shapiro et al., 2011*), Lingua Franca (*Lohstroh et al., 2021*), Esterel and Lustre.
* Data parallelism: NESL (*Blelloch, 1996*), Futhark (*Henriksen et al., PLDI 2017*), Halide (*Ragan-Kelley et al., PLDI 2013*), Accelerate (*Chakravarty et al., 2011*).
* Runtimes: OCaml 5 effects and Eio (*Sivaramakrishnan et al., PLDI 2021*), Erlang/OTP (*Armstrong, 2003*), Elm (*Czaplicki & Chong, PLDI 2013*), Trio nurseries, Java Loom, Kotlin structured concurrency, Go.
* Durable execution: Golem, Temporal, Restate, DBOS, Azure Durable Functions, Cloudflare Durable Objects, Flawless, CRIU, Smalltalk images.

</details>

<details>
<summary>Projects</summary>

* Languages: Scala 3 and scalafmt (`// format: off`), Flix, Koka, Effekt, Unison, Rust (Drop, Send and Sync, Polonius), OCaml (modules), Zig (`zig cc` is our C compiler), Go, Lean 4, Hazel, Racket's Turnstile, Ioke, Zed.
* Datalog and logic engines: Soufflé, egglog, Datafrog, Ascent, FlowLog, Nemo, datalevin, faster-miniKanren, Chez Scheme's intmap, klogic, Doop, nanofil, SWI-Prolog, Trealla, clingo.
* Memory and runtimes: Fil-C, mimalloc, musl, libmprompt, minicoro, Clojure's persistent collections.
* Our own: [fx-rs](https://github.com/denful/fx-rs) (effects), [yen](https://github.com/vic/yen) (Datalog in Nix, and the flake this repo runs on), [dnx](https://github.com/denful/dnx), a Nix runtime on [persistent delta interaction nets](https://github.com/vic/persistent-delta-interaction-nets/blob/main/pidnets.pdf), the reason srs exists.

</details>

## Support

srs is made and maintained by **vic**. Issues, pull requests and [sponsors](https://github.com/sponsors/vic) are welcome.
