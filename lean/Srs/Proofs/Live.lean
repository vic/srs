/-
L2.3 (part 1): liveness in the GENERATED checker. `live`/`needLive` (s1/check.srs) against `liveS`, and the
name-read case of `chk`: a value read is only accepted when every region it captures is live (no use-after-free).
-/
import Srs.Proofs.Gamma

set_option autoImplicit false

namespace Srs.Proofs
open Srs.Impl Srs.Rt

def t1 : «Node» → ByteArray
  | .«Node» _ s _ _ _ _ => s
  | .«NoNode» => ByteArray.empty
def t2 : «Node» → ByteArray
  | .«Node» _ _ t _ _ _ => t
  | .«NoNode» => ByteArray.empty
def nm : «Node» → Int
  | .«Node» _ _ _ n _ _ => n
  | .«NoNode» => 0

theorem text_t1 (h : «Node») : «text» h = some (t1 h) := by cases h <;> rfl
theorem text2_t2 (h : «Node») : «text2» h = some (t2 h) := by cases h <;> rfl
theorem num_nm (h : «Node») : «num» h = some (nm h) := by cases h <;> rfl
def isNode : «Node» → Bool
  | .«NoNode» => false
  | _ => true
theorem found_eq (h : «Node») : «found» h = some (isNode h) := by cases h <;> rfl
theorem t1_node (k : «Kind») (s t : ByteArray) (n l : Int) (a : «Nodes») : t1 (.«Node» k s t n l a) = s := rfl
theorem t1_data (h : «Node») : (t1 h).data = txt h := by cases h <;> rfl

def dropN : Nat → «Nodes» → «Nodes»
  | 0, c => c
  | n + 1, c => dropN n (tlN c)

theorem nth_w_spec (i : Int) (xs : «Nodes») :
    ∀ (n : Nat) (k : Int) (c : «Nodes»), k.toNat = n → ∃ k', «nth_w100» k c i xs = some (k', dropN n c)
  | 0, k, c, hk => ⟨k, by
      rw [«nth_w100»]
      have : ¬ k > 0 := by omega
      simp [this, pure, dropN]⟩
  | n + 1, k, c, hk => by
    obtain ⟨k', hc⟩ := nth_w_spec i xs n (k - 1) (tlN c) (by omega)
    refine ⟨k', ?_⟩
    rw [«nth_w100»]
    have : k > 0 := by omega
    simp [this, tail_eq, bind, Option.bind, hc, dropN]

theorem kid_spec (x : «Node») (i : Int) : «kid» x i = some (hdN (dropN i.toNat (ks x))) := by
  obtain ⟨k', hc⟩ := nth_w_spec i (ks x) i.toNat i (ks x) rfl
  simp [«kid», «nth», kids_eq, bind, Option.bind, hc, head_eq]

/-- spec of live: c is not a capability, or its state is not an end state of its protocol -/
def liveS (ds env gam : «Nodes») (c : ByteArray) : Bool :=
  match (lkp .«BVar» c (toL env)).getD .«NoNode» with
  | .«NoNode» => true
  | .«Node» _ _ p n _ _ =>
    if n != 2 then true
    else !decide ((t2 ((lkp .«GState» c (toL gam)).getD .«NoNode»)).data ∈
      names (ks (hdN (dropN 1 (ks ((lkp .«DProto» p (toL ds)).getD .«NoNode»))))))

theorem live_spec (ds env gam : «Nodes») (c : ByteArray) : «live» ds env gam c = some (liveS ds env gam c) := by
  unfold «live» liveS
  cases hb : (lkp .«BVar» c (toL env)).getD .«NoNode» with
  | «NoNode» => simp [find_spec, hb, found_eq, isNode, bind, Option.bind, pure]
  | «Node» k s p n l a =>
    by_cases hn : n = 2
    · simp [find_spec, hb, found_eq, isNode, num_nm, nm, hn, «protoEnds», «state», kid_spec, kids_eq, text2_t2, t2,
        has_spec, bind, Option.bind, pure]
      exact decide_eq_decide.mpr Iff.rfl
    · simp [find_spec, hb, found_eq, isNode, num_nm, nm, hn, bind, Option.bind, pure]

theorem needLive_w_spec (ds env gam : «Nodes») (t : «Node») (line : Int) :
    ∀ c : «Nodes», «needLive_w94» c line t gam env ds =
      if ∀ x ∈ toL c, liveS ds env gam (t1 x) = true then some .«NNil» else none
  | .«NNil» => by rw [«needLive_w94»]; simp [«isNil», toL, pure]
  | .«NCons» h tl => by
    rw [«needLive_w94»]
    by_cases hl : liveS ds env gam (t1 h) = true
    · simp [«isNil», head_eq, hdN_cons, tail_eq, tlN_cons, text_t1, live_spec, hl, bind, Option.bind,
        needLive_w_spec ds env gam t line tl, toL]
    · simp [«isNil», head_eq, hdN_cons, text_t1, live_spec, hl, err_none, bind, Option.bind, toL]

/-- the generated `needLive`: accepts iff every capture of t is live, else the run stops -/
theorem needLive_spec (ds env gam : «Nodes») (t : «Node») (line : Int) :
    «needLive» ds env gam t line =
      if ∀ x ∈ toL (tlN (ks t)), liveS ds env gam (t1 x) = true then some () else none := by
  simp only [«needLive», «tyCaps», kids_eq, tail_eq, bind, Option.bind, needLive_w_spec]
  by_cases hall : ∀ x ∈ toL (tlN (ks t)), liveS ds env gam (t1 x) = true
  · rw [ite_eq_left hall, ite_eq_left hall]; rfl
  · rw [ite_eq_right hall, ite_eq_right hall]

/-- C8 + no use-after-free, on the GENERATED checker: `chk` accepts reading a var only when every region
the var holds NOW (its GVar flow caps in Γ) is live. -/
theorem chk_var_live (ds env gam : «Nodes») (x y : ByteArray) (n line : Int) (a : «Nodes») (tg : «TG»)
    (k' : «Kind») (s' p' : ByteArray) (l' : Int) (a' : «Nodes»)
    (hb : (lkp .«BVar» x (toL env)).getD .«NoNode» = .«Node» k' s' p' 1 l' a')
    (h : «chk» ds env gam (.«Node» .«XName» x y n line a) = some tg) :
    ∀ c ∈ toL (ks ((lkp .«GVar» x (toL gam)).getD .«NoNode»)), liveS ds env gam (t1 c) = true := by
  rw [«chk»] at h
  by_cases hall : ∀ c ∈ toL (ks ((lkp .«GVar» x (toL gam)).getD .«NoNode»)), liveS ds env gam (t1 c) = true
  · exact hall
  · exfalso
    simp only [kind_eq, kd, «lineOf», text_t1, t1_node, find_spec, hb, found_eq, isNode, num_nm, nm, kid_spec, «mkTy»,
      «leaf», kids_eq, bind, Option.bind, pure, needLive_spec] at h
    simp only [ks, tlN, t1] at h hall
    simp [hall] at h

end Srs.Proofs
