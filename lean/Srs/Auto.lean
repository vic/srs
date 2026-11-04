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
