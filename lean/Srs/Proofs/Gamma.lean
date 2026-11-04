/-
L2.2: the GENERATED Γ helpers of s1/check.srs (find, rev, setG, within, joinGam, err) against list specs.
Γ = Nodes of GState(cap, state) and GVar(var, caps). These are the operations `chk` threads Γ with.
-/
import Srs.Proofs.Lists

set_option autoImplicit false

namespace Srs.Proofs
open Srs.Impl Srs.Rt

def toL : «Nodes» → List «Node»
  | .«NNil» => []
  | .«NCons» h t => h :: toL t

def ofL : List «Node» → «Nodes»
  | [] => .«NNil»
  | h :: t => .«NCons» h (ofL t)

theorem toL_ofL (l : List «Node») : toL (ofL l) = l := by
  induction l with
  | nil => rfl
  | cons h t ih => simp [ofL, toL, ih]

theorem ofL_toL : ∀ (x : «Nodes»), ofL (toL x) = x
  | .«NNil» => rfl
  | .«NCons» h t => by simp [toL, ofL, ofL_toL t]

def kd : «Node» → «Kind»
  | .«Node» k _ _ _ _ _ => k
  | .«NoNode» => .«TEof»

def ks : «Node» → «Nodes»
  | .«Node» _ _ _ _ _ a => a
  | .«NoNode» => .«NNil»

theorem kind_eq (h : «Node») : «kind» h = some (kd h) := by cases h <;> rfl
theorem kids_eq (h : «Node») : «kids» h = some (ks h) := by cases h <;> rfl
def txt2 : «Node» → Array UInt8
  | .«Node» _ _ t _ _ _ => t.data
  | .«NoNode» => "".toUTF8.data

theorem text2_eq (h : «Node») : ∃ b, «text2» h = some b ∧ b.data = txt2 h := by
  cases h <;> exact ⟨_, rfl, rfl⟩

/-- `err` stops the run: rt_exit -/
theorem err_none (w n : ByteArray) (l : Int) : «err» w n l = none := by
  simp [«err», rt_eprint, rt_eprint_i64, rt_exit, bind, Option.bind, pure]

/-- first node of kind k and text s -/
def lkp (k : «Kind») (s : ByteArray) : List «Node» → Option «Node»
  | [] => none
  | h :: t => if kd h = k ∧ txt h = s.data then some h else lkp k s t

theorem find_w_spec (s : ByteArray) (k : «Kind») (xs : «Nodes») :
    ∀ (c : «Nodes») (found : Bool) (res : «Node»), ∃ f c',
      «find_w142» found res c s k xs = some (f, (if found then res else (lkp k s (toL c)).getD res), c')
  | .«NNil», found, res => ⟨found, .«NNil», by rw [«find_w142»]; cases found <;> rfl⟩
  | .«NCons» h t, true, res => ⟨true, .«NCons» h t, by rw [«find_w142»]; rfl⟩
  | .«NCons» h t, false, res => by
    obtain ⟨b, hb, hbd⟩ := text_eq h
    by_cases hm : kd h = k ∧ txt h = s.data
    · obtain ⟨f, c', hc⟩ := find_w_spec s k xs t true h
      refine ⟨f, c', ?_⟩
      rw [«find_w142»]
      have hb' : (b.data == s.data) = true := by simp [hbd, hm.2]
      simp only [«isNil», «head», «tail», «eqs», rt_str_eq, kind_eq, hb, hm.1, hb', bind, Option.bind,
        pure, hc]
      simp [toL, lkp, hm]
    · obtain ⟨f, c', hc⟩ := find_w_spec s k xs t false res
      refine ⟨f, c', ?_⟩
      rw [«find_w142»]
      simp only [«isNil», «head», «tail», «eqs», rt_str_eq, kind_eq, hb, bind, Option.bind, pure]
      by_cases e : kd h = k
      · have hne : (b.data == s.data) = false := by
          rw [hbd]; exact beq_false_of_ne (fun x => hm ⟨e, x⟩)
        have ht : ¬ txt h = s.data := fun x => hm ⟨e, x⟩
        simp [e, hne, hc, toL, lkp, ht]
      · simp [e, hc, toL, lkp]

/-- the generated `find`: the first match, else NoNode -/
theorem find_spec (xs : «Nodes») (k : «Kind») (s : ByteArray) :
    «find» xs k s = some ((lkp k s (toL xs)).getD .«NoNode») := by
  obtain ⟨f, c', hc⟩ := find_w_spec s k xs xs false .«NoNode»
  simp only [«find», bind, Option.bind, pure, hc]
  simp

theorem rev_w_spec (xs : «Nodes») :
    ∀ (c out : «Nodes»), ∃ c', «rev_w115» c out xs = some (c', ofL ((toL c).reverse ++ toL out))
  | .«NNil», out => ⟨.«NNil», by rw [«rev_w115»]; simp [«isNil», toL, bind, Option.bind, pure, ofL_toL]⟩
  | .«NCons» h t, out => by
    obtain ⟨c', hc⟩ := rev_w_spec xs t (.«NCons» h out)
    refine ⟨c', ?_⟩
    rw [«rev_w115»]
    simp [«isNil», «head», «tail», bind, Option.bind, pure, hc, toL]

theorem rev_spec (xs : «Nodes») : «rev» xs = some (ofL (toL xs).reverse) := by
  obtain ⟨c', hc⟩ := rev_w_spec xs xs .«NNil»
  simp [«rev», bind, Option.bind, pure, hc, toL]

/-- setG spec: replace the first entry of x's kind and name by x -/
def repl (x : «Node») : Bool → List «Node» → List «Node»
  | _, [] => []
  | done, h :: t => if done = false ∧ kd h = kd x ∧ txt h = txt x then x :: repl x true t else h :: repl x done t

theorem setG_w_spec (x : «Node») (gam : «Nodes») :
    ∀ (c out : «Nodes») (done : Bool), ∃ d,
      «setG_w55» done c out x gam = some (d, .«NNil», ofL ((repl x done (toL c)).reverse ++ toL out))
  | .«NNil», out, done => ⟨done, by rw [«setG_w55»]; simp [«isNil», bind, Option.bind, pure, repl, toL, ofL_toL]⟩
  | .«NCons» h t, out, done => by
    obtain ⟨b, hb, hbd⟩ := text_eq h
    obtain ⟨bx, hbx, hbxd⟩ := text_eq x
    by_cases hm : done = false ∧ kd h = kd x ∧ txt h = txt x
    · obtain ⟨d, hc⟩ := setG_w_spec x gam t (.«NCons» x out) true
      refine ⟨d, ?_⟩
      rw [«setG_w55»]
      have hbe : (b.data == bx.data) = true := by rw [hbd, hbxd, hm.2.2]; exact beq_self_eq_true _
      simp [«isNil», «head», «tail», «eqs», rt_str_eq, kind_eq, hb, hbx, hm.1, hm.2.1, hm.2.2, hbe, bind,
        Option.bind, pure, hc, repl, toL]
    · obtain ⟨d, hc⟩ := setG_w_spec x gam t (.«NCons» h out) done
      refine ⟨d, ?_⟩
      rw [«setG_w55»]
      have hcond : ((!done && decide (kd h = kd x)) && (b.data == bx.data)) = false := by
        cases done <;> by_cases e : kd h = kd x <;> simp_all
      simp only [«isNil», «head», «tail», «eqs», rt_str_eq, kind_eq, hb, hbx, bind, Option.bind, pure]
      cases done <;> by_cases e : kd h = kd x <;> simp_all [repl, toL]

/-- the generated `setG` = repl -/
theorem setG_spec (gam : «Nodes») (x : «Node») : «setG» gam x = some (ofL (repl x false (toL gam))) := by
  obtain ⟨d, hc⟩ := setG_w_spec x gam gam .«NNil» false
  simp [«setG», bind, Option.bind, hc, rev_spec, toL_ofL, toL]

def hdN : «Nodes» → «Node»
  | .«NNil» => .«NoNode»
  | .«NCons» h _ => h
def tlN : «Nodes» → «Nodes»
  | .«NNil» => .«NNil»
  | .«NCons» _ t => t

/-- the caps of h within the caps of y -/
def capsIn (h y : «Node») : Bool := decide (∀ n ∈ names (ks h), n ∈ names (ks y))

theorem subset_kids (h y : «Node») : «subset» (ks h) (ks y) = some (capsIn h y) := subset_spec _ _

/-- within spec: each entry's caps within the same-position entry of the other Γ (C8 loop check) -/
def withinS : «Nodes» → «Nodes» → Bool
  | .«NNil», _ => true
  | .«NCons» h t, ys => capsIn h (hdN ys) && withinS t (tlN ys)

theorem within_w_spec (b a : «Nodes») :
    ∀ (x y : «Nodes») (ok : Bool), ∃ y' x', «within_w78» ok y x b a = some (ok && withinS x y, y', x')
  | .«NNil», y, ok => ⟨y, .«NNil», by rw [«within_w78»]; cases ok <;> simp [«isNil», withinS, bind, Option.bind, pure]⟩
  | .«NCons» h t, y, false => ⟨y, .«NCons» h t, by rw [«within_w78»]; rfl⟩
  | .«NCons» h t, y, true => by
    obtain ⟨y', x', hc⟩ := within_w_spec b a t (tlN y) (capsIn h (hdN y))
    refine ⟨y', x', ?_⟩
    rw [«within_w78»]
    cases y <;> simp only [hdN, tlN] at hc <;>
      simp [«isNil», «head», «tail», kids_eq, subset_kids, bind, Option.bind, pure, withinS, hdN, tlN, hc]

theorem within_spec (a b : «Nodes») : «within» a b = some (withinS a b) := by
  obtain ⟨y', x', hc⟩ := within_w_spec b a a b true
  simp [«within», bind, Option.bind, pure, hc]

theorem hdN_cons (h : «Node») (t : «Nodes») : hdN (.«NCons» h t) = h := rfl
theorem tlN_cons (h : «Node») (t : «Nodes») : tlN (.«NCons» h t) = t := rfl
theorem head_eq (y : «Nodes») : «head» y = some (hdN y) := by cases y <;> rfl
theorem tail_eq (y : «Nodes») : «tail» y = some (tlN y) := by cases y <;> rfl

/-- if/match join precondition: same-position entries in the same state -/
def Agree : «Nodes» → «Nodes» → Prop
  | .«NNil», _ => True
  | .«NCons» h t, ys => txt2 h = txt2 (hdN ys) ∧ Agree t (tlN ys)

/-- joinGam result: entry by entry, h's kind, name and state, caps = union of both (C8) -/
inductive JoinS : «Nodes» → «Nodes» → List «Node» → Prop
  | nil (ys : «Nodes») : JoinS .«NNil» ys []
  | cons (h : «Node») (t ys : «Nodes») (j : «Node») (r : List «Node») :
    kd j = kd h → txt j = txt h → txt2 j = txt2 h →
    (∀ n, n ∈ names (ks j) ↔ n ∈ names (ks h) ∨ n ∈ names (ks (hdN ys))) →
    JoinS t (tlN ys) r → JoinS (.«NCons» h t) ys (j :: r)

theorem joinGam_w_ok (line : Int) (what : ByteArray) (b a : «Nodes») :
    ∀ (x y out : «Nodes»), Agree x y → ∃ y' x' r,
      «joinGam_w67» y x out line what b a = some (y', x', ofL (r.reverse ++ toL out)) ∧ JoinS x y r
  | .«NNil», y, out, _ => ⟨y, .«NNil», [], by rw [«joinGam_w67»]; simp [«isNil», bind, Option.bind, pure, ofL_toL],
      JoinS.nil y⟩
  | .«NCons» h t, y, out, ⟨hs, ht⟩ => by
    obtain ⟨bt, hbt, hbtd⟩ := text_eq h
    obtain ⟨b2, hb2, hb2d⟩ := text2_eq h
    obtain ⟨b2y, hb2y, hb2yd⟩ := text2_eq (hdN y)
    obtain ⟨u, hu, hum⟩ := union_spec (ks h) (ks (hdN y))
    let j : «Node» := .«Node» (kd h) bt b2 0 0 u
    obtain ⟨y', x', r, hc, hj⟩ := joinGam_w_ok line what b a t (tlN y) (.«NCons» j out) ht
    refine ⟨y', x', j :: r, ?_, JoinS.cons h t y j r rfl hbtd hb2d hum hj⟩
    rw [«joinGam_w67»]
    have he : b2.data = b2y.data := by rw [hb2d, hb2yd, hs]
    simp [«isNil», hdN_cons, tlN_cons, head_eq, tail_eq, «eqs», rt_str_eq, kind_eq, kids_eq, hbt, hb2, hb2y, he, hu, bind,
      Option.bind, pure, hc, j, toL]

theorem joinGam_w_bad (line : Int) (what : ByteArray) (b a : «Nodes») :
    ∀ (x y out : «Nodes»), ¬ Agree x y → «joinGam_w67» y x out line what b a = none
  | .«NNil», _, _, hn => absurd trivial hn
  | .«NCons» h t, y, out, hn => by
    obtain ⟨bt, hbt, _⟩ := text_eq h
    obtain ⟨b2, hb2, hb2d⟩ := text2_eq h
    obtain ⟨b2y, hb2y, hb2yd⟩ := text2_eq (hdN y)
    obtain ⟨u, hu, _⟩ := union_spec (ks h) (ks (hdN y))
    rw [«joinGam_w67»]
    by_cases hs : txt2 h = txt2 (hdN y)
    · have ht : ¬ Agree t (tlN y) := fun x => hn ⟨hs, x⟩
      have he : b2.data = b2y.data := by rw [hb2d, hb2yd, hs]
      simp [«isNil», hdN_cons, tlN_cons, head_eq, tail_eq, «eqs», rt_str_eq, kind_eq, kids_eq, hbt, hb2, hb2y, he, hu, bind,
        Option.bind, pure, joinGam_w_bad line what b a t (tlN y) _ ht]
    · have he : ¬ b2.data = b2y.data := by rw [hb2d, hb2yd]; exact hs
      simp [«isNil», hdN_cons, head_eq, «eqs», rt_str_eq, hb2, hb2y, he, hbt, err_none, bind, Option.bind]

/-- the generated `joinGam`: none (the run stops) iff some entry pair disagrees in state; else the join -/
theorem joinGam_spec (a b : «Nodes») (what : ByteArray) (line : Int) :
    (Agree a b → ∃ r, «joinGam» a b what line = some (ofL r) ∧ JoinS a b r) ∧
    (¬ Agree a b → «joinGam» a b what line = none) := by
  constructor
  · intro h
    obtain ⟨y', x', r, hc, hj⟩ := joinGam_w_ok line what b a a b .«NNil» h
    exact ⟨r, by simp [«joinGam», bind, Option.bind, hc, rev_spec, toL_ofL, toL], hj⟩
  · intro h
    simp [«joinGam», bind, Option.bind, joinGam_w_bad line what b a a b .«NNil» h]

end Srs.Proofs
