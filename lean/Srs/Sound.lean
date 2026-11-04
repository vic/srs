/-
Soundness of the srs flow checker: a program the checker accepts never reaches a runtime error
(no double free, alloc after free, use-after-free, protocol order/cardinality break, or leaked cap).
-/
import Srs.Model

set_option autoImplicit false

namespace Srs

theorem lget_lset {α : Type} (d : α) (l : List α) (x i : Nat) (a : α) :
    lget d (lset d l x a) i = if i = x then a else lget d l i := by
  induction l generalizing x i with
  | nil =>
    induction x generalizing i with
    | zero => cases i <;> simp [lset, lget]
    | succ n ih => cases i <;> simp [lset, lget, ih]
  | cons y ys ih => cases x <;> cases i <;> simp [lset, lget, ih]

theorem lget_vjoin (a b : Vars) (i : Nat) :
    lget [] (vjoin a b) i = lget [] a i ++ lget [] b i := by
  induction a generalizing b i with
  | nil => simp [vjoin, lget]
  | cons x xs ih =>
    cases b with
    | nil => cases i <;> simp [vjoin, lget]
    | cons y ys => cases i <;> simp [vjoin, lget, ih]

/-- runtime var caps within abstract var caps -/
abbrev VLe (r a : Vars) : Prop := ∀ i c, c ∈ lget [] r i → c ∈ lget [] a i

theorem vleB_sound (r a : Vars) : vleB r a = true → VLe r a := by
  induction r generalizing a with
  | nil => intro _ i c hc; cases i <;> simp [lget] at hc
  | cons x xs ih =>
    cases a with
    | nil =>
      intro h i c hc
      simp [vleB] at h
      cases i with
      | zero => simp [lget, h.1] at hc
      | succ i => simpa [lget] using ih [] h.2 i c (by simpa [lget] using hc)
    | cons y ys =>
      intro h i c hc
      simp [vleB] at h
      cases i with
      | zero => simpa [lget] using h.1 c (by simpa [lget] using hc)
      | succ i => simpa [lget] using ih ys h.2 i c (by simpa [lget] using hc)

theorem vle_trans {a b c : Vars} (h1 : VLe a b) (h2 : VLe b c) : VLe a c :=
  fun i x h => h2 i x (h1 i x h)

theorem vle_join_l (a b : Vars) : VLe a (vjoin a b) := by
  intro i c h; rw [lget_vjoin]; exact List.mem_append_left _ h

theorem vle_join_r (a b : Vars) : VLe b (vjoin a b) := by
  intro i c h; rw [lget_vjoin]; exact List.mem_append_right _ h

theorem vle_set {r a : Vars} {cr ca : List Nat} (x : Nat) (h : VLe r a) (hc : ∀ c ∈ cr, c ∈ ca) :
    VLe (lset [] r x cr) (lset [] a x ca) := by
  intro i c hi
  rw [lget_lset] at hi ⊢
  split <;> simp_all

/-- runtime state r is abstracted by a: cap states exact, var caps over-approximated -/
structure Abs (r a : St) : Prop where
  caps : r.caps = a.caps
  vars : VLe r.vars a.vars

variable (P : Nat → Proto)

/-- an expression the checker accepts on abstract vars runs on runtime vars: same cap states,
value caps within the abstract ones -/
theorem evalE_mono {rv av : Vars} (hv : VLe rv av) (e : Expr) :
    ∀ cs cs' ca, evalE P cs av e = some (cs', ca) →
      ∃ cr, evalE P cs rv e = some (cs', cr) ∧ ∀ c ∈ cr, c ∈ ca := by
  induction e with
  | nil => intro cs cs' ca h; simp [evalE] at h; obtain ⟨rfl, rfl⟩ := h; exact ⟨[], by simp [evalE], by simp⟩
  | rd y =>
    intro cs cs' ca h
    simp only [evalE] at h
    split at h
    · rename_i hall
      simp only [Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      have : (lget [] rv y).all (live P cs) = true := by
        rw [List.all_eq_true] at hall ⊢; exact fun c hc => hall c (hv y c hc)
      exact ⟨lget [] rv y, by simp [evalE, this], fun c hc => hv y c hc⟩
    · cases h
  | alloc c o => intro cs cs' ca h; exact ⟨ca, by simpa [evalE] using h, fun _ x => x⟩
  | pair a b iha ihb =>
    intro cs cs' ca h
    simp only [evalE] at h
    cases ha : evalE P cs av a with
    | none => simp [ha] at h
    | some p =>
      obtain ⟨cs1, x⟩ := p
      cases hb : evalE P cs1 av b with
      | none => simp [ha, hb] at h
      | some q =>
        obtain ⟨cs2, y⟩ := q
        simp [ha, hb] at h
        obtain ⟨rfl, rfl⟩ := h
        obtain ⟨xr, hxr, hx⟩ := iha cs cs1 x ha
        obtain ⟨yr, hyr, hy⟩ := ihb cs1 cs2 y hb
        refine ⟨xr ++ yr, by simp [evalE, hxr, hyr], ?_⟩
        intro c hc
        simp only [List.mem_append] at hc ⊢
        exact hc.imp (hx c) (hy c)

theorem loopFix_spec (f : St → Option St) : ∀ n g gs, loopFix f n g = some gs →
    g.caps = gs.caps ∧ VLe g.vars gs.vars ∧
      ∃ g', f gs = some g' ∧ g'.caps = gs.caps ∧ vleB g'.vars gs.vars = true := by
  intro n
  induction n with
  | zero => intro g gs h; simp [loopFix] at h
  | succ n ih =>
    intro g gs h
    simp only [loopFix] at h
    cases hf : f g with
    | none => simp [hf] at h
    | some g' =>
      simp only [hf] at h
      by_cases hc : g'.caps = g.caps
      · by_cases hv : vleB g'.vars g.vars = true
        · simp [hc, hv] at h
          subst h
          exact ⟨rfl, fun _ _ x => x, g', hf, hc, hv⟩
        · simp [hc, hv] at h
          obtain ⟨h1, h2, h3⟩ := ih _ _ h
          exact ⟨h1, vle_trans (vle_join_l _ _) h2, h3⟩
      · simp [hc] at h

/-- soundness: what the checker accepts, from an abstraction of the runtime state, runs without
error, and the abstraction holds after -/
theorem sound (fuel : Nat) {s : Stmt} {r : St} {res : Res} (hr : Run P s r res) :
    ∀ a a', check P fuel s a = some a' → Abs r a → ∃ r', res = .ok r' ∧ Abs r' a' := by
  induction hr with
  | skip => intro a a' h ha; simp [check] at h; subst h; exact ⟨_, rfl, ha⟩
  | op_ok hs =>
    intro a a' h ha
    simp only [check] at h
    rw [← ha.caps, hs] at h
    simp at h; subst h
    exact ⟨_, rfl, ⟨rfl, ha.vars⟩⟩
  | op_err hs =>
    intro a a' h ha
    simp only [check] at h
    rw [← ha.caps, hs] at h
    simp at h
  | @asg_ok s x e cs v he =>
    intro a a' h ha
    simp only [check] at h
    cases he' : evalE P a.caps a.vars e with
    | none => simp [he'] at h
    | some p =>
      obtain ⟨cs', va⟩ := p
      simp [he'] at h; subst h
      obtain ⟨vr, hvr, hsub⟩ := evalE_mono P ha.vars e a.caps cs' va he'
      rw [← ha.caps, he] at hvr
      simp only [Option.some.injEq, Prod.mk.injEq] at hvr
      obtain ⟨rfl, rfl⟩ := hvr
      exact ⟨_, rfl, ⟨rfl, vle_set _ ha.vars hsub⟩⟩
  | @asg_err s x e he =>
    intro a a' h ha
    simp only [check] at h
    cases he' : evalE P a.caps a.vars e with
    | none => simp [he'] at h
    | some p =>
      obtain ⟨vr, hvr, _⟩ := evalE_mono P ha.vars e a.caps p.1 p.2 he'
      rw [← ha.caps, he] at hvr
      cases hvr
  | @use_ok s e cs v he =>
    intro a a' h ha
    simp only [check] at h
    cases he' : evalE P a.caps a.vars e with
    | none => simp [he'] at h
    | some p =>
      obtain ⟨cs', va⟩ := p
      simp [he'] at h; subst h
      obtain ⟨vr, hvr, _⟩ := evalE_mono P ha.vars e a.caps cs' va he'
      rw [← ha.caps, he] at hvr
      simp only [Option.some.injEq, Prod.mk.injEq] at hvr
      obtain ⟨rfl, rfl⟩ := hvr
      exact ⟨_, rfl, ⟨rfl, ha.vars⟩⟩
  | @use_err s e he =>
    intro a a' h ha
    simp only [check] at h
    cases he' : evalE P a.caps a.vars e with
    | none => simp [he'] at h
    | some p =>
      obtain ⟨vr, hvr, _⟩ := evalE_mono P ha.vars e a.caps p.1 p.2 he'
      rw [← ha.caps, he] at hvr
      cases hvr
  | @seq_ok a0 b0 s t r _ _ ih1 ih2 =>
    intro g g' h ha
    simp only [check] at h
    cases hc : check P fuel a0 g with
    | none => simp [hc] at h
    | some gt =>
      simp only [hc] at h
      obtain ⟨r', hr', ht⟩ := ih1 g gt hc ha
      cases hr'
      exact ih2 gt g' h ht
  | @seq_err a0 b0 s _ ih1 =>
    intro g g' h ha
    simp only [check] at h
    cases hc : check P fuel a0 g with
    | none => simp [hc] at h
    | some gt =>
      obtain ⟨_, hr', _⟩ := ih1 g gt hc ha
      cases hr'
  | @ite_l a0 b0 s r _ ih =>
    intro g g' h ha
    simp only [check] at h
    cases hA : check P fuel a0 g with
    | none => simp [hA] at h
    | some ga =>
      cases hB : check P fuel b0 g with
      | none => simp [hA, hB] at h
      | some gb =>
        simp only [hA, hB] at h
        split at h
        · simp only [Option.some.injEq] at h; subst h
          obtain ⟨r', hr', hab⟩ := ih g ga hA ha
          exact ⟨r', hr', ⟨hab.caps, vle_trans hab.vars (vle_join_l _ _)⟩⟩
        · cases h
  | @ite_r a0 b0 s r _ ih =>
    intro g g' h ha
    simp only [check] at h
    cases hA : check P fuel a0 g with
    | none => simp [hA] at h
    | some ga =>
      cases hB : check P fuel b0 g with
      | none => simp [hA, hB] at h
      | some gb =>
        simp only [hA, hB] at h
        split at h
        · rename_i heq
          simp only [Option.some.injEq] at h; subst h
          obtain ⟨r', hr', hab⟩ := ih g gb hB ha
          exact ⟨r', hr', ⟨hab.caps.trans heq.symm, vle_trans hab.vars (vle_join_r _ _)⟩⟩
        · cases h
  | loop_done =>
    intro a a' h ha
    simp only [check] at h
    obtain ⟨hc, hv, _⟩ := loopFix_spec _ _ _ _ h
    exact ⟨_, rfl, ⟨ha.caps.trans hc, vle_trans ha.vars hv⟩⟩
  | @loop_more b0 s t r _ _ ih1 ih2 =>
    intro a a' h ha
    simp only [check] at h
    obtain ⟨hc, hv, g', hf, hgc, hgv⟩ := loopFix_spec _ _ _ _ h
    obtain ⟨r', hr', ht⟩ := ih1 a' g' hf ⟨ha.caps.trans hc, vle_trans ha.vars hv⟩
    cases hr'
    have hfix : loopFix (check P fuel b0) fuel a' = some a' := by
      cases fuel with
      | zero => simp [loopFix] at h
      | succ k => simp [loopFix, hf, hgc, hgv]
    exact ih2 a' a' (by simpa only [check] using hfix)
      ⟨ht.caps.trans hgc, vle_trans ht.vars (vleB_sound _ _ hgv)⟩
  | @loop_err b0 s _ ih1 =>
    intro a a' h ha
    simp only [check] at h
    obtain ⟨hc, hv, g', hf, _, _⟩ := loopFix_spec _ _ _ _ h
    obtain ⟨_, hr', _⟩ := ih1 a' g' hf ⟨ha.caps.trans hc, vle_trans ha.vars hv⟩
    cases hr'
  | @hdl_ok c b0 s t cs hn _ hcl ih =>
    intro a a' h ha
    simp only [check] at h
    rw [← ha.caps, hn] at h
    simp only at h
    cases hb : check P fuel b0 ⟨lset none s.caps c (some (P c).start), a.vars⟩ with
    | none => simp [hb] at h
    | some gt =>
      simp only [hb] at h
      obtain ⟨r', hr', ht⟩ := ih _ _ hb ⟨rfl, ha.vars⟩
      cases hr'
      rw [← ht.caps, hcl] at h
      simp at h; subst h
      exact ⟨_, rfl, ⟨rfl, ht.vars⟩⟩
  | hdl_reuse hn =>
    intro a a' h ha
    simp only [check] at h
    rw [← ha.caps] at h
    cases hx : lget none _ _ with
    | none => exact absurd hx hn
    | some _ => simp [hx] at h
  | @hdl_err c b0 s hn _ ih =>
    intro a a' h ha
    simp only [check] at h
    rw [← ha.caps, hn] at h
    simp only at h
    cases hb : check P fuel b0 ⟨lset none s.caps c (some (P c).start), a.vars⟩ with
    | none => simp [hb] at h
    | some gt =>
      obtain ⟨_, hr', _⟩ := ih _ _ hb ⟨rfl, ha.vars⟩
      cases hr'
  | @hdl_leak c b0 s t hn _ hcl ih =>
    intro a a' h ha
    simp only [check] at h
    rw [← ha.caps, hn] at h
    simp only at h
    cases hb : check P fuel b0 ⟨lset none s.caps c (some (P c).start), a.vars⟩ with
    | none => simp [hb] at h
    | some gt =>
      simp only [hb] at h
      obtain ⟨r', hr', ht⟩ := ih _ _ hb ⟨rfl, ha.vars⟩
      cases hr'
      rw [← ht.caps, hcl] at h
      simp at h

/-- an accepted program never errs at runtime -/
theorem no_error (fuel : Nat) {s : Stmt} {g g' : St} (h : check P fuel s g = some g') :
    ¬ Run P s g .err := by
  intro hr
  obtain ⟨_, hr', _⟩ := sound P fuel hr g g' h ⟨rfl, fun _ _ x => x⟩
  cases hr'

end Srs
