/-
L2 bottom rung: theorems about the GENERATED S1 (Srs.Impl, from s1/node.srs + s1/check.srs), not a copy.
`has`/`subset` are the set operations under the checker's cap bookkeeping (needLive, assignable, C8 within).
-/
import Srs.Impl.S1

set_option autoImplicit false

namespace Srs.Proofs
open Srs.Impl Srs.Rt

/-- spec: the text of a node, as the bytes rt_str_eq compares -/
def txt : «Node» → Array UInt8
  | .«Node» _ s _ _ _ _ => s.data
  | .«NoNode» => "".toUTF8.data

def names : «Nodes» → List (Array UInt8)
  | .«NNil» => []
  | .«NCons» h t => txt h :: names t

theorem text_eq (h : «Node») : ∃ b, «text» h = some b ∧ b.data = txt h := by
  cases h <;> exact ⟨_, rfl, rfl⟩

theorem has_w_spec (s : ByteArray) (xs : «Nodes») :
    ∀ (c : «Nodes») (found : Bool), ∃ c',
      «has_loop0» found c s xs = some (found || decide (s.data ∈ names c), c')
  | .«NNil», found => ⟨.«NNil», by rw [«has_loop0»]; cases found <;> rfl⟩
  | .«NCons» h t, true => ⟨.«NCons» h t, by rw [«has_loop0»]; rfl⟩
  | .«NCons» h t, false => by
    obtain ⟨b, hb, hbd⟩ := text_eq h
    obtain ⟨c', hc⟩ := has_w_spec s xs t (b.data == s.data)
    refine ⟨c', ?_⟩
    rw [«has_loop0»]
    simp only [«isNil», «head», «tail», «eqs», rt_str_eq, hb, bind, Option.bind, pure, hc]
    have hbeq : (b.data == s.data) = decide (s.data = b.data) := by
      by_cases e : s.data = b.data
      · simp [e]
      · simp only [e, decide_false]; exact beq_false_of_ne (fun x => e x.symm)
    simp [names, ← hbd, hbeq]

/-- the generated `has` terminates and decides membership -/
theorem has_spec (xs : «Nodes») (s : ByteArray) : «has» xs s = some (decide (s.data ∈ names xs)) := by
  obtain ⟨c', hc⟩ := has_w_spec s xs xs false
  simp only [«has», bind, Option.bind, pure, hc]
  simp

theorem subset_w_spec (b a : «Nodes») :
    ∀ (c : «Nodes») (ok : Bool), ∃ c',
      «subset_loop0» ok c b a = some (ok && decide (∀ x ∈ names c, x ∈ names b), c')
  | .«NNil», ok => ⟨.«NNil», by rw [«subset_loop0»]; cases ok <;> simp [«isNil», names, bind, Option.bind, pure]⟩
  | .«NCons» h t, false => ⟨.«NCons» h t, by rw [«subset_loop0»]; rfl⟩
  | .«NCons» h t, true => by
    obtain ⟨y, hy, hyd⟩ := text_eq h
    obtain ⟨c', hc⟩ := subset_w_spec b a t (decide (y.data ∈ names b))
    refine ⟨c', ?_⟩
    rw [«subset_loop0»]
    simp only [«isNil», «head», «tail», hy, has_spec, bind, Option.bind, pure, hc]
    simp [names, ← hyd]

/-- the generated `subset` terminates and decides inclusion of names -/
theorem subset_spec (a b : «Nodes») :
    «subset» a b = some (decide (∀ x ∈ names a, x ∈ names b)) := by
  obtain ⟨c', hc⟩ := subset_w_spec b a a true
  simp only [«subset», bind, Option.bind, pure, hc]
  simp

theorem union_w_spec (b a : «Nodes») :
    ∀ (c out : «Nodes»), ∃ c' out', «union_loop0» c out b a = some (c', out') ∧
      ∀ x, x ∈ names out' ↔ x ∈ names out ∨ x ∈ names c
  | .«NNil», out => ⟨.«NNil», out, by rw [«union_loop0»]; rfl, by simp [names]⟩
  | .«NCons» h t, out => by
    obtain ⟨y, hy, hyd⟩ := text_eq h
    by_cases hin : y.data ∈ names out
    · obtain ⟨c', out', hc, hm⟩ := union_w_spec b a t out
      refine ⟨c', out', ?_, ?_⟩
      · rw [«union_loop0»]
        simp [«isNil», «head», «tail», hy, has_spec, hin, bind, Option.bind, pure, hc]
      · intro x; rw [hm]; simp only [names, List.mem_cons, ← hyd]
        constructor
        · rintro (hx | hx) <;> simp_all
        · rintro (hx | rfl | hx) <;> simp_all
    · obtain ⟨c', out', hc, hm⟩ := union_w_spec b a t (.«NCons» h out)
      refine ⟨c', out', ?_, ?_⟩
      · rw [«union_loop0»]
        simp [«isNil», «head», «tail», hy, has_spec, hin, bind, Option.bind, pure, hc]
      · intro x; rw [hm]; simp only [names, List.mem_cons, ← hyd]
        constructor
        · rintro ((rfl | hx) | hx) <;> simp_all
        · rintro (hx | rfl | hx) <;> simp_all

/-- the generated `union` terminates and its names are exactly the names of both -/
theorem union_spec (a b : «Nodes») :
    ∃ u, «union» a b = some u ∧ ∀ x, x ∈ names u ↔ x ∈ names a ∨ x ∈ names b := by
  obtain ⟨c', out', hc, hm⟩ := union_w_spec b a b a
  exact ⟨out', by simp only [«union», bind, Option.bind, pure, hc], hm⟩

end Srs.Proofs
