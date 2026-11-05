# AGENTS.md: how to work on srs

srs is a Scala3-surface language that compiles to portable C. It has no GC. Memory, mutability and protocols are
effects, checked at compile time. The compiler is written in srs (S1, `s1/`). A frozen C copy of S1
(`bootstrap/seed.c`) builds it. A Lean 4 model and proofs (`lean/`) cover the checker. Vic owns every design
decision. You implement what vic rules, with evidence.

## 1. Find out what to do

Read these in this order before you do anything:

1. `vic/HANDOFF.md`: the current state and the `NEXT-CMD`.
2. The open beads: `cd vic && br list --status open`. The tracker is `br` in `vic/.beads`. The parent bead tells
   you the order (`br show <id>`).
3. The design for the bead, for example `vic/c/binders-design.md`. Its `RULED` sections are law. Its proposal
   sections are not.
4. The rulings: `vic/c/rulings/C*.md`, plus the rulings sections in
   `vic/notes/20261104T2330--compiler-substrates-macros-typing-facts__design_research_laik.md`.
5. The quipu ledger: `ledger:srs/ruling/`, `ledger:srs/evidence/`, `ledger:srs/mistake/`.

If a decision is not ruled, it is not yours to make. Write the question to the design file and ask vic.

## 2. How vic works

- Design comes first. Do not write code before vic says "go" for that rung. "Show how X looks" means syntax in
  chat, not code.
- Ask one precise question. Show srs code for each option. Give your recommendation. Do not give a menu of
  options without a recommendation.
- Vic answers in short lines ("Q1: yes. Q2: ..."). Record each answer verbatim, in the design file and in quipu
  (`ledger:srs/ruling/<slug>`), before you act on it.
- A new ruling replaces an old one. Mark what it replaces. Do not keep a superseded rule alive.
- Do not invent rules. If vic did not say it, label it as an idea.
- When you find a bug outside the task, file a bead (`br create`) and continue. Do not fix it in passing.
- When the plan meets a gap in the code (for example, the checker has no check mode), stop. Write down the gap,
  with `file:line` evidence. Propose the fix and the smaller fallback, then wait. Vic decides on changes to the
  architecture.

## 3. Rulings that shape all work

- Type level is pure, finite, complete and deterministic. A fuel limit or "no answer" is a reject, never
  "unknown".
- One language: type level is the pure, finite part of srs. There is no second type-level language.
- Order: Kanren with constraints, then Datalog, then binders and telescopes. Δ-Nets are deferred
  (bead vic-z95).
- Binder groups: `()` values, `[A: Type]` type ascription (A is ascribed the type Type), `{s: Show[A]}` evidence (always named; a capability = handler presence `{r: Region}`),
  `<at(f, s)>` Datalog facts. Type application is `T[args]` ([] = types, the Scala3 surface). At a call: `f[T](x)` gives type args, `f{a}(x)` chooses evidence/caps; otherwise they are found (local evidence first, as Scala3). Caps on a type are facts: `List[I64]^<r>`. Facts after the return type are the exit facts.
- `<>` holds Datalog atoms and rules only. There is no regex protocol syntax.
- `spec def` takes no groups. `extern def` takes all groups as a trusted contract. A slot of an extern typed by a `{}` binder
  is `void*`.
- Fuel: each disj split and each clause pick costs 1. An ambiguous summon is a reject. Datalog negation is
  stratified only.

## 4. The rung loop

Each rung is small, at most about one hour:

1. Write the oracle first: a pass test with `.out`, and a negative test in `tests/neg/` with `// expect: <error>`.
2. Implement the smallest change.
3. Run the gates (section 5).
4. Run mutants. Each mutant breaks one rule in the code, and at least one test must fail. If a mutant
   survives, the tests have a gap: add a test, then run the mutant again.
5. Commit with jj. Record the evidence in quipu (`ledger:srs/evidence/<slug>`): the commands, the output, the
   controls and the verdict. Update `vic/HANDOFF.md` and prepend to `vic/state.md`.
6. Report to vic: what works, the evidence, what is not done, and the next rung.

For a refactor, the oracle is identical output. Save the C of every test before the change, then compare it
byte for byte after. Add an armed control: a mutant that must change the output.

## 5. Gates and commands

- `./tests/run.sh` (devshell `srs-test`): the fixpoint, the seed, every pass test, every neg test. Timeouts are
  built in.
- After any change to `s1/*.srs`: run `./tests/run.sh`, then
  `cp ${XDG_RUNTIME_DIR}/srs-build/s2.c bootstrap/seed.c` (`seed-update`), then `./tests/run.sh` again.
- lean-check, always under a memory cap and never under `vic-run` (its `ulimit -v` kills Lean threads):
  `timeout 900 systemd-run --user --scope -q -p MemoryMax=12G nix develop -c lean-check`.
  The first run after an S1 change regenerates `lean/Srs/Impl/S1.lean` and fails. Run it twice. A pass shows
  `proof lean (debt): 0`, `Impl verdicts = S1: N pass, M neg` and `Build completed successfully`.
- Get the real exit code: `cmd > log 2>&1; echo EXIT=$?`. A pipe into `tail` hides it.
- The build dir is `B=${XDG_RUNTIME_DIR}/srs-build` (set by `tests/run.sh`). To test a single file fast:
  `$B/s2 lib/prelude.srs lib/kanren.srs lib/datalog.srs tests/list.lib tests/file.lib tests/x.srs > $B/x.c`,
  then `zig cc -std=gnu11 -O1 -w -o $B/x $B/x.c rt/srs_rt.c`, then run `$B/x`.
- To test a mutant of S1: build S1 from `$B/seed` with the changed source, then run only the affected tests.

Lists you must keep in sync:

- A new `lib/*.srs` goes in three places: `LIBS` in `tests/run.sh`, `libs` in `lean/Srs/ImplRun.lean`, and a
  `gen` line in `nix/commands.nix`, with its import in `lean/Srs.lean`.
- A new `s1/*.srs` goes in `S1SRC` in `tests/run.sh` and in `nix/commands.nix` (two places).

## 6. srs facts that bite

- S1 source is compiled by the seed. It can only use features that the seed already supports.
- srs has no closures and no value lambdas. Write goals, streams and rules as data (enums) and an interpreter.
- A constructor call needs a `Region` in scope. A function that builds nodes needs an `r: Region` parameter.
- srs has no string concatenation. Name things structurally, for example an instance is a callee plus its type
  arguments, and the emitter prints the parts.
- All files share one namespace. Constructor and function names must be unique across libs and tests. S1 does
  not catch a duplicate `def` (bead vic-gkz); only `zig cc` does.
- Make invalid data impossible to build. For example, `Dom(h, t)` is a non-empty domain, and the input facts
  have their own type `Edb`. Prefer a type with exactly the right cases to a type with impossible cases.
- Lean traps are listed in `vic/notes/20261104T2200--lean4-proof-traps__lean_srs_proofs.md`. Read the list before
  you touch `s1/lean.srs`, `s1/leanspec.srs` or `lean/Srs/Auto.lean`.

## 7. Do not

- Do not write code before vic's go, and do not widen the scope of a rung.
- Do not use git. Use jj. There are two workspaces: the main one (`/home/vic/hk/srs`) and the docs one
  (`/home/vic/hk/srs/vic`). Commit in each one separately. Never push.
- Do not use Python. Do not use multiline perl or sed edits: use the Edit tool. For a mechanical edit across
  many call sites, test the regex on a sample line first and check the result with `rg`.
- Do not trust a mutant that `sed` did not change, or that changed more than one place. Check with `cmp` and
  `rg -n` before you run it.
- Do not read a test failure without its message. A mutant that fails for the wrong reason (a name error
  instead of the checked rule) proves nothing.
- Do not claim "done", "green" or "works" without the command and its output in the same report.
- Do not hide a slip. Record your own mistakes in `ledger:srs/mistake/` and tell vic.
- Do not suppress warnings, skip tests or work around a hard bug. Find the root cause with a minimal repro first.
