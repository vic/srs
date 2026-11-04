/-
`srs_auto`: the default prover of srs contracts (C13 P4). A tactic: the Lean kernel checks every proof it
builds, so it is not trusted. `proof using a, b` in srs adds a, b as simp facts.
-/
syntax "srs_auto" (" [" Lean.Parser.Tactic.simpLemma,* "]")? : tactic

macro_rules
  | `(tactic| srs_auto) => `(tactic| srs_auto [])
  | `(tactic| srs_auto [$ls,*]) => `(tactic| (
      simp only [bind, Option.bind, pure] at *
      first
        | (simp_all [$ls,*]; done)
        | (simp_all [$ls,*] <;> omega)
        | (refine ⟨_, rfl, ?_⟩ <;> simp_all [$ls,*])))

namespace Srs

/-- every srs `while` compiles to this: run `body` while `cond` holds (C13 P1 loops) -/
def loop {σ : Type} (cond : σ → Option Bool) (body : σ → Option σ) (s : σ) : Option σ := do
  if (← cond s) then loop cond body (← body s) else pure s
partial_fixpoint

/-- the one loop theorem: an invariant that holds on entry, is kept by one turn, and a measure that drops each
turn ⟹ the loop ends, with the invariant and the condition false. Per srs loop only `hstep` is left to prove. -/
theorem loop_inv {σ : Type} (cond : σ → Option Bool) (body : σ → Option σ) (I : σ → Prop) (D : σ → Nat)
    (hstep : ∀ s, I s → ∃ b, cond s = some b ∧ (b = true → ∃ s', body s = some s' ∧ I s' ∧ D s' < D s)) :
    ∀ s, I s → ∃ r, loop cond body s = some r ∧ I r ∧ cond r = some false := by
  intro s
  induction h : D s using Nat.strongRecOn generalizing s with
  | _ n ih =>
    intro hI
    obtain ⟨b, hc, hb⟩ := hstep s hI
    rw [loop]
    cases b with
    | false => exact ⟨s, by simp [hc, bind, Option.bind, pure], hI, hc⟩
    | true =>
      obtain ⟨s', hs', hI', hd⟩ := hb rfl
      obtain ⟨r, hr, hIr, hcr⟩ := ih (D s') (h ▸ hd) s' rfl hI'
      exact ⟨r, by simp [hc, hs', hr, bind, Option.bind], hIr, hcr⟩

end Srs
