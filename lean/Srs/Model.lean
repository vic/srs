/-
srs-core effect model (vic/c/effects.md). Runtime semantics `Run` and the flow checker `check`.
The checker is an abstract interpretation: the same `evalE` runs on abstract state, whose var caps
over-approximate the runtime ones (C8) and whose cap states are exact (protocols are deterministic).
-/
set_option autoImplicit false

namespace Srs

/-- a protocol = automaton (effects.md "protocol = automaton"): states and ops are numbers -/
structure Proto where
  start : Nat
  isEnd : Nat → Bool
  trans : Nat → Nat → Option Nat -- op → state → next state; none = no transition
  drop : Option Nat -- op run at scope end when the state is not an end state

/-- lists as total maps with a default: reads past the end give `d`, writes extend -/
def lget {α : Type} (d : α) : List α → Nat → α
  | [], _ => d
  | x :: _, 0 => x
  | _ :: xs, n + 1 => lget d xs n

def lset {α : Type} (d : α) : List α → Nat → α → List α
  | [], 0, a => [a]
  | [], n + 1, a => d :: lset d [] n a
  | _ :: xs, 0, a => a :: xs
  | x :: xs, n + 1, a => x :: lset d xs n a

/-- cap c ↦ protocol state; none = not created yet (a handle creates it once) -/
abbrev Caps := List (Option Nat)
/-- var x ↦ the caps (regions) its value lives in -/
abbrev Vars := List (List Nat)

structure St where
  caps : Caps
  vars : Vars

inductive Expr where
  | nil -- nullary ctor: static, `T^{}`
  | rd (y : Nat) -- read var y
  | alloc (c o : Nat) -- ctor in region c: op o (alloc) on c, the value lives in c
  | pair (a b : Expr) -- ctor with fields: captures what its fields capture

inductive Stmt where
  | skip
  | op (c o : Nat) -- protocol op on cap c
  | asg (x : Nat) (e : Expr) -- var x = e
  | use (e : Expr)
  | seq (a b : Stmt)
  | ite (a b : Stmt) -- the condition is abstract: either branch may run
  | loop (b : Stmt) -- any number of turns
  | hdl (c : Nat) (b : Stmt) -- handle c: create in start state, run b, end (drop op if needed)

variable (P : Nat → Proto)

/-- cap c is live: created and not in an end state -/
def live (cs : Caps) (c : Nat) : Bool :=
  match lget none cs c with
  | some s => !(P c).isEnd s
  | none => false

/-- op o on cap c: a transition of c's protocol from its state, else none -/
def step (cs : Caps) (c o : Nat) : Option Caps :=
  match lget none cs c with
  | some s =>
    match (P c).trans o s with
    | some t => some (lset none cs c (some t))
    | none => none
  | none => none

/-- an expression: new cap states and the caps of its value; none = an error -/
def evalE (cs : Caps) (vs : Vars) : Expr → Option (Caps × List Nat)
  | .nil => some (cs, [])
  | .rd y => if (lget [] vs y).all (live P cs) then some (cs, lget [] vs y) else none
  | .alloc c o =>
    match step P cs c o with
    | some cs' => some (cs', [c])
    | none => none
  | .pair a b =>
    match evalE cs vs a with
    | some (cs1, x) =>
      match evalE cs1 vs b with
      | some (cs2, y) => some (cs2, x ++ y)
      | none => none
    | none => none

/-- scope end of cap c: in an end state, or its drop op takes it to one -/
def close (cs : Caps) (c : Nat) : Option Caps :=
  match lget none cs c with
  | some s =>
    if (P c).isEnd s then some cs
    else
      match (P c).drop with
      | some o =>
        match (P c).trans o s with
        | some t => if (P c).isEnd t then some (lset none cs c (some t)) else none
        | none => none
      | none => none
  | none => none

inductive Res where
  | ok (s : St)
  | err

/-- runtime semantics. `err` = the srs errors: op with no transition (double free, alloc after free,
READ x3, CLOSE w/o READ), read of a value whose region ended (use-after-free), cap created twice,
scope end not in an end state (missing CLOSE) -/
inductive Run : Stmt → St → Res → Prop
  | skip {s : St} : Run .skip s (.ok s)
  | op_ok {s : St} {c o : Nat} {cs : Caps} :
    step P s.caps c o = some cs → Run (.op c o) s (.ok ⟨cs, s.vars⟩)
  | op_err {s : St} {c o : Nat} : step P s.caps c o = none → Run (.op c o) s .err
  | asg_ok {s : St} {x : Nat} {e : Expr} {cs : Caps} {v : List Nat} :
    evalE P s.caps s.vars e = some (cs, v) → Run (.asg x e) s (.ok ⟨cs, lset [] s.vars x v⟩)
  | asg_err {s : St} {x : Nat} {e : Expr} : evalE P s.caps s.vars e = none → Run (.asg x e) s .err
  | use_ok {s : St} {e : Expr} {cs : Caps} {v : List Nat} :
    evalE P s.caps s.vars e = some (cs, v) → Run (.use e) s (.ok ⟨cs, s.vars⟩)
  | use_err {s : St} {e : Expr} : evalE P s.caps s.vars e = none → Run (.use e) s .err
  | seq_ok {a b : Stmt} {s t : St} {r : Res} : Run a s (.ok t) → Run b t r → Run (.seq a b) s r
  | seq_err {a b : Stmt} {s : St} : Run a s .err → Run (.seq a b) s .err
  | ite_l {a b : Stmt} {s : St} {r : Res} : Run a s r → Run (.ite a b) s r
  | ite_r {a b : Stmt} {s : St} {r : Res} : Run b s r → Run (.ite a b) s r
  | loop_done {b : Stmt} {s : St} : Run (.loop b) s (.ok s)
  | loop_more {b : Stmt} {s t : St} {r : Res} :
    Run b s (.ok t) → Run (.loop b) t r → Run (.loop b) s r
  | loop_err {b : Stmt} {s : St} : Run b s .err → Run (.loop b) s .err
  | hdl_ok {c : Nat} {b : Stmt} {s t : St} {cs : Caps} :
    lget none s.caps c = none → Run b ⟨lset none s.caps c (some (P c).start), s.vars⟩ (.ok t) →
    close P t.caps c = some cs → Run (.hdl c b) s (.ok ⟨cs, t.vars⟩)
  | hdl_reuse {c : Nat} {b : Stmt} {s : St} : lget none s.caps c ≠ none → Run (.hdl c b) s .err
  | hdl_err {c : Nat} {b : Stmt} {s : St} :
    lget none s.caps c = none → Run b ⟨lset none s.caps c (some (P c).start), s.vars⟩ .err →
    Run (.hdl c b) s .err
  | hdl_leak {c : Nat} {b : Stmt} {s t : St} :
    lget none s.caps c = none → Run b ⟨lset none s.caps c (some (P c).start), s.vars⟩ (.ok t) →
    close P t.caps c = none → Run (.hdl c b) s .err

/-- pointwise union of var caps (if/match join, loop widening) -/
def vjoin : Vars → Vars → Vars
  | [], b => b
  | a :: as, [] => a :: as
  | a :: as, b :: bs => (a ++ b) :: vjoin as bs

/-- every var of r has caps within the same var of a -/
def vleB : Vars → Vars → Bool
  | [], _ => true
  | r :: rs, [] => r.isEmpty && vleB rs []
  | r :: rs, a :: as => r.all (fun c => decide (c ∈ a)) && vleB rs as

/-- loop: widen var caps until the body keeps them (fixpoint, C8); cap states must not change -/
def loopFix (f : St → Option St) : Nat → St → Option St
  | 0, _ => none
  | n + 1, g =>
    match f g with
    | some g' =>
      if g'.caps = g.caps then
        if vleB g'.vars g.vars then some g else loopFix f n ⟨g.caps, vjoin g.vars g'.vars⟩
      else none
    | none => none

/-- the flow checker: Γ1 ⊢ s ⊣ Γ2. none = rejected. `fuel` bounds loop widening -/
def check (fuel : Nat) : Stmt → St → Option St
  | .skip, g => some g
  | .op c o, g =>
    match step P g.caps c o with
    | some cs => some ⟨cs, g.vars⟩
    | none => none
  | .asg x e, g =>
    match evalE P g.caps g.vars e with
    | some (cs, v) => some ⟨cs, lset [] g.vars x v⟩
    | none => none
  | .use e, g =>
    match evalE P g.caps g.vars e with
    | some (cs, _) => some ⟨cs, g.vars⟩
    | none => none
  | .seq a b, g =>
    match check fuel a g with
    | some t => check fuel b t
    | none => none
  | .ite a b, g =>
    match check fuel a g, check fuel b g with
    | some ga, some gb => if ga.caps = gb.caps then some ⟨ga.caps, vjoin ga.vars gb.vars⟩ else none
    | _, _ => none
  | .loop b, g => loopFix (check fuel b) fuel g
  | .hdl c b, g =>
    match lget none g.caps c with
    | none =>
      match check fuel b ⟨lset none g.caps c (some (P c).start), g.vars⟩ with
      | some t =>
        match close P t.caps c with
        | some cs => some ⟨cs, t.vars⟩
        | none => none
      | none => none
    | some _ => none

end Srs
