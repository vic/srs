/-
`srs_auto`: the default prover of srs contracts (C13 P4). A tactic: the Lean kernel checks every proof it
builds, so it is not trusted. `proof using a, b` in srs adds a, b as simp facts.
-/
import Srs.Rt


syntax "srs_auto" (" [" Lean.Parser.Tactic.simpLemma,* "]")? : tactic

macro_rules
  | `(tactic| srs_auto) => `(tactic| srs_auto [])
  | `(tactic| srs_auto [$ls,*]) => `(tactic| (
      (try simp only [bind, Option.bind, pure, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at,
        Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at,
        Srs.Rt.P.rt_str_slice] at *)
      first
        | done
        | (simp_all [$ls,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice]; done)
        | (simp_all [$ls,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Int.max_eq_left] <;> omega)
        | ((repeat' split) <;> simp_all [$ls,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice, Int.max_eq_left] <;> (first | done | omega))
        | (refine ⟨_, rfl, ?_⟩ <;> simp_all [$ls,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice])
        | ((try simp_all [$ls,*, Srs.Rt.rt_str_eq, Srs.Rt.rt_str_len, Srs.Rt.rt_str_at, Srs.Rt.rt_str_slice, Srs.Rt.P.rt_str_eq, Srs.Rt.P.rt_str_len, Srs.Rt.P.rt_str_at, Srs.Rt.P.rt_str_slice]) <;> grind)))

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

end Srs
