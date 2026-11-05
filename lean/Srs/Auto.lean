/-
`srs_auto`: the default prover of srs contracts (C13 P4). A tactic: the Lean kernel checks every proof it
builds, so it is not trusted. `proof using a, b` in srs adds a, b as simp facts.
-/
import Srs.Rt

/-- a bind on an `if` (a body `if` whose condition calls fns): push the bind into both arms. Used before
`bind` unfolds to `match`, where the `if` would be stuck in the match scrutinee. -/
theorem Srs.ite_bind {α β : Type} (c : Prop) [Decidable c] (a b : Option α) (f : α → Option β) :
    (ite c a b >>= f) = ite c (a >>= f) (b >>= f) := by split <;> rfl

/-- a bind on a known value (an `f_eq` rewrite gives `some E`) -/
theorem Srs.some_bind {α β : Type} (a : α) (f : α → Option β) : (some a >>= f) = f a := rfl

namespace Srs

/-- `returns` (C15): P holds of the value, if `o` returns one (`none` = the run stopped: no claim) -/
def ok {α : Type} (o : Option α) (P : α → Prop) : Prop := ∀ x, o = some x → P x

theorem ok_intro {α : Type} {o : Option α} {P : α → Prop} (h : ok o P) : ∀ x, o = some x → P x := h
theorem ok_none {α : Type} (P : α → Prop) : ok none P = True := by simp [ok]
theorem ok_some {α : Type} (a : α) (P : α → Prop) : ok (some a) P = P a := by simp [ok]
theorem ok_pure {α : Type} (a : α) (P : α → Prop) : ok (pure a) P = P a := by simp [ok, pure]
theorem ok_bind {α β : Type} (x : Option α) (f : α → Option β) (P : β → Prop) :
    ok (x >>= f) P = ok x (fun a => ok (f a) P) := by
  cases x <;> simp [ok, bind, Option.bind]
theorem ok_ite {α : Type} (c : Prop) [Decidable c] (a b : Option α) (P : α → Prop) :
    ok (ite c a b) P = ite c (ok a P) (ok b P) := by split <;> rfl
/-- no claim on the value (a loop w/o invariant: the claim holds for any loop result) -/
theorem ok_true {α : Type} (o : Option α) : ok o (fun _ => True) = True := by simp [ok]
/-- a callee with `returns E`: its value comes with E (generated `f_ok`; the rhs has no `ok`, so simp stops) -/
theorem ok_ret {α : Type} {o : Option α} {E : α → Prop} (h : ∀ r, o = some r → E r) (P : α → Prop) :
    ok o P = ∀ r, o = some r → E r → P r :=
  propext ⟨fun hp r hr _ => hp r hr, fun hp r hr => hp r hr (h r hr)⟩

end Srs

-- facts = idents: each goes to simp and to grind
syntax "srs_auto" (" [" ident,* "]")? : tactic

open Lean in
macro_rules
  | `(tactic| srs_auto) => `(tactic| srs_auto [])
  | `(tactic| srs_auto [$ls,*]) => do
    let ls := ls.getElems
    let ss ← ls.mapM fun i => `(Lean.Parser.Tactic.simpLemma| $i:ident)
    let gs ← ls.mapM fun i => `(Lean.Parser.Tactic.grindParam| $i:ident)
    `(tactic| (
      (try simp only [$ss,*, pure_bind, Srs.some_bind, Srs.ite_bind, Srs.ok_none, Srs.ok_some, Srs.ok_pure, Srs.ok_bind, Srs.ok_ite, Srs.ok_true, Srs.Rt.rt_str_eq, Srs.Rt.rt_eprint, Srs.Rt.rt_eprint_i64, Srs.Rt.rt_exit] at *)
      (try simp only [bind, Option.bind, pure, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Srs.Rt.rt_print, Srs.Rt.rt_eprint, Srs.Rt.rt_print_i64, Srs.Rt.rt_eprint_i64, Srs.Rt.rt_exit] at *)
      first
        | done
        | (simp_all [$ss,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Srs.Rt.rt_print, Srs.Rt.rt_eprint, Srs.Rt.rt_print_i64, Srs.Rt.rt_eprint_i64, Srs.Rt.rt_exit, Srs.ok_none, Srs.ok_some, Srs.ok_pure, Srs.ok_bind, Srs.ok_ite, Srs.ok_true]; done)
        | (simp_all [$ss,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Srs.Rt.rt_print, Srs.Rt.rt_eprint, Srs.Rt.rt_print_i64, Srs.Rt.rt_eprint_i64, Srs.Rt.rt_exit, Srs.ok_none, Srs.ok_some, Srs.ok_pure, Srs.ok_bind, Srs.ok_ite, Srs.ok_true, Int.max_eq_left, Int.add_nonneg] <;> omega)
        | ((repeat' split) <;> simp_all [$ss,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Srs.Rt.rt_print, Srs.Rt.rt_eprint, Srs.Rt.rt_print_i64, Srs.Rt.rt_eprint_i64, Srs.Rt.rt_exit, Srs.ok_none, Srs.ok_some, Srs.ok_pure, Srs.ok_bind, Srs.ok_ite, Srs.ok_true, Int.max_eq_left, Int.add_nonneg] <;> (first | done | omega))
        | ((repeat' split) <;> (repeat' apply And.intro) <;> simp_all [$ss,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Srs.Rt.rt_print, Srs.Rt.rt_eprint, Srs.Rt.rt_print_i64, Srs.Rt.rt_eprint_i64, Srs.Rt.rt_exit, Srs.ok_none, Srs.ok_some, Srs.ok_pure, Srs.ok_bind, Srs.ok_ite, Srs.ok_true, Int.max_eq_left, Int.add_nonneg] <;> (first | done | omega))
        | ((refine ⟨_, rfl, ?_⟩ <;> simp_all [$ss,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Srs.Rt.rt_print, Srs.Rt.rt_eprint, Srs.Rt.rt_print_i64, Srs.Rt.rt_eprint_i64, Srs.Rt.rt_exit, Srs.ok_none, Srs.ok_some, Srs.ok_pure, Srs.ok_bind, Srs.ok_ite, Srs.ok_true]); done)
        | ((repeat' split) <;> (try simp_all [$ss,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Srs.Rt.rt_print, Srs.Rt.rt_eprint, Srs.Rt.rt_print_i64, Srs.Rt.rt_eprint_i64, Srs.Rt.rt_exit, Srs.ok_none, Srs.ok_some, Srs.ok_pure, Srs.ok_bind, Srs.ok_ite, Srs.ok_true, Int.max_eq_left, Int.add_nonneg]) <;> grind [$gs,*])
        | ((try simp_all [$ss,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Srs.Rt.rt_print, Srs.Rt.rt_eprint, Srs.Rt.rt_print_i64, Srs.Rt.rt_eprint_i64, Srs.Rt.rt_exit, Srs.ok_none, Srs.ok_some, Srs.ok_pure, Srs.ok_bind, Srs.ok_ite, Srs.ok_true]) <;> grind [$gs,*])
        -- ok unfolded: grind picks the witness of an `exists` claim (a value only the run knows, e.g. a loop result)
        | (simp only [Srs.ok] at *; intros; grind [$gs,*])))


namespace Srs

/-- the one loop theorem: every srs `while` aux unfolds as `aux cap st = do if (← cond st)
then aux cap (← body st) else pure st`. An invariant kept by one turn and a measure that drops ⟹ the loop
ends with the invariant and the condition false. -/
theorem loop_inv {σ : Type} (f : σ → Option σ) (cond : σ → Option Bool) (body : σ → Option σ)
    (hf : ∀ s, f s = (do if (← cond s) then f (← body s) else pure s)) (I : σ → Prop) (D : σ → Nat)
    (hstep : ∀ s, I s → ∃ b, cond s = some b ∧ (b = true → ∃ s', body s = some s' ∧ I s' ∧ D s' < D s)) :
    ∀ s, I s → ∃ r, f s = some r ∧ I r ∧ cond r = some false := by
  intro s
  induction h : D s using Nat.strongRecOn generalizing s with
  | _ n ih =>
    intro hI
    obtain ⟨b, hc, hb⟩ := hstep s hI
    rw [hf]
    cases b with
    | false => exact ⟨s, by simp [hc, bind, Option.bind, pure], hI, hc⟩
    | true =>
      obtain ⟨s', hs', hI', hd⟩ := hb rfl
      obtain ⟨r, hr, hIr, hcr⟩ := ih (D s') (h ▸ hd) s' rfl hI'
      exact ⟨r, by simp [hc, hs', hr, bind, Option.bind], hIr, hcr⟩

/-- a loop followed by the rest `k` of its fn: the fn's contract from the loop invariant at exit -/
theorem loop_bind {σ β : Type} (f : σ → Option σ) (cond : σ → Option Bool) (body : σ → Option σ)
    (hf : ∀ s, f s = (do if (← cond s) then f (← body s) else pure s)) (I : σ → Prop) (D : σ → Nat)
    (hstep : ∀ s, I s → ∃ b, cond s = some b ∧ (b = true → ∃ s', body s = some s' ∧ I s' ∧ D s' < D s))
    (s : σ) (k : σ → Option β) (P : β → Prop) (hI : I s)
    (hk : ∀ r, I r → cond r = some false → ∃ v, k r = some v ∧ P v) :
    ∃ v, (f s >>= k) = some v ∧ P v := by
  obtain ⟨r, hr, hIr, hcr⟩ := loop_inv f cond body hf I D hstep s hI
  obtain ⟨v, hv, hP⟩ := hk r hIr hcr
  exact ⟨v, by simp [hr, hv, bind, Option.bind], hP⟩

/-- the loop theorem when the run may stop. A turn that returns keeps the invariant and drops the measure ⟹
a loop that returns ends with the invariant and the condition false. -/
theorem loop_ret {σ : Type} (f : σ → Option σ) (cond : σ → Option Bool) (body : σ → Option σ)
    (hf : ∀ s, f s = (do if (← cond s) then f (← body s) else pure s)) (I : σ → Prop) (D : σ → Nat)
    (hstep : ∀ s, I s → ∀ b, cond s = some b → b = true → ok (body s) (fun s' => I s' ∧ D s' < D s)) :
    ∀ s, I s → ok (f s) (fun r => I r ∧ cond r = some false) := by
  intro s
  induction h : D s using Nat.strongRecOn generalizing s with
  | _ n ih =>
    intro hI r hr
    rw [hf] at hr
    cases hc : cond s with
    | none => simp [hc, bind, Option.bind] at hr
    | some b =>
      cases b with
      | false =>
        simp [hc, bind, Option.bind, pure] at hr
        exact hr ▸ ⟨hI, hc⟩
      | true =>
        cases hb : body s with
        | none => simp [hc, hb, bind, Option.bind] at hr
        | some s' =>
          simp [hc, hb, bind, Option.bind] at hr
          obtain ⟨hI', hd⟩ := hstep s hI true hc rfl s' hb
          exact ih (D s') (h ▸ hd) s' rfl hI' r hr

/-- a loop followed by the rest `k` of its fn: the fn's `returns` fact from the loop invariant at exit -/
theorem loop_ret_bind {σ β : Type} (f : σ → Option σ) (cond : σ → Option Bool) (body : σ → Option σ)
    (hf : ∀ s, f s = (do if (← cond s) then f (← body s) else pure s)) (I : σ → Prop) (D : σ → Nat)
    (hstep : ∀ s, I s → ∀ b, cond s = some b → b = true → ok (body s) (fun s' => I s' ∧ D s' < D s))
    (s : σ) (k : σ → Option β) (P : β → Prop) (hI : I s)
    (hk : ∀ r, I r → cond r = some false → ok (k r) P) :
    ok (f s >>= k) P := by
  intro v hv
  cases hr : f s with
  | none => simp [hr, bind, Option.bind] at hv
  | some r =>
    simp [hr, bind, Option.bind] at hv
    obtain ⟨hIr, hcr⟩ := loop_ret f cond body hf I D hstep s hI r hr
    exact hk r hIr hcr v hv

end Srs
