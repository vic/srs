# srs

srs is a programming language for people who want fast, small programs and want the compiler to prove they are safe.

You write code that reads like a high-level language. You get plain C out of it: no garbage collector, no runtime
surprises, no hidden costs. And before anything runs, srs has already checked that your program can't read freed
memory, can't index past the end of an array, and can't use a resource in the wrong order.

## Memory without a garbage collector, without the bookkeeping

Memory lives in regions. You open a region, allocate in it, and free it all at once when you are done. srs follows
every value to the region it lives in, so using something after its region is gone is a compile error, not a crash at
3am.

```scala
def work {r: Srs.Region} {s: Srs.Region} <r: Open> (a: List<s>, b: List): I64 <r: Freed> =
  val n = sum(b)
  r.free()
  sum(a) + n
```

`work` frees `r` and keeps using `a`, and that is fine: `a` lives in `s`. Use `b` after `r.free()` and srs stops you.
There are no ownership annotations to learn: you name a region only when you want to choose one.

## Arrays that know their length

The length of an array is part of its type, and every index has to be proven in range. There are no bounds checks at
run time because there is nothing left to check.

```scala
def get(n: I64, xs: Array[I64](n), i: I64): I64 =
  if 0 <= i && i < n then xs(i) else 0
```

## Types that compute

Types can take values and branch on them. srs runs the code at compile time, so the program you ship already has the
answer.

```scala
type Bits (n: I64) = n match
  case 8 => Bool
  case _ => I64

def dbl(x: I64): I64 = x * 2
def flag(x: Bits(dbl(4))): Bool = !x
```

## Effects you can see, protocols you can't break

Everything a function does beyond computing a value is an effect: printing, files, sockets, writing to an array. An
effect shows up in the types, and someone has to handle it, so nothing escapes `main` by accident.

A capability can also carry a protocol: the states it moves through and which operations are allowed in each one. You
can even give the protocol your own rules, and srs checks every call against them.

```scala
capability Door:
  state Shut, Open1, Open2, Gone
  start Shut
  stop Gone
  transition knock Shut -> Open1, Open1 -> Open2
  def knock <s knock t> (): I64 <t>
  transition leave Open1 -> Gone, Open2 -> Gone
  def leave <s leave t> (): Unit <t>
  rule def twoKnocks(s, s3) = next(s, knock, s2), next(s2, knock, s3)

def knockTwice {d: Door} <d: s, twoKnocks(s, s3)> (): I64 <d: s3> =
  val a = d.knock()
  a + d.knock()
```

Leaving a door that was never opened, or forgetting to leave it, is a compile error. Handlers decide what an effect
means, and they can resume a computation more than once, which makes search and backtracking feel natural.

## Every answer has a reason

Each check srs makes is a small logical fact with the rule that produced it. When srs says no, it says which rule, and
you can ask why. When it says yes, that yes is something it proved, not something it guessed.

## A living program, not a pile of files

An srs program is an image you talk to while it runs. You add, change and remove definitions, and each change is
checked in full before it is accepted, so the image is never in a broken state. Definitions are identified by what they
mean, not by their names: rename something and nothing that depends on it changes. Tests and negative tests (programs
that must be rejected, with the reason why) live inside the image next to the code they protect.

srs builds itself. The compiler in this repository reads its own image and writes out exactly the C it was built from,
and every change has to keep that true.

## Try it

You need [Nix](https://nixos.org).

```console
$ nix build
$ nix develop
$ just
```

`./srs` has the whole compiler as srs source, one definition per file, so you can read how it works.
