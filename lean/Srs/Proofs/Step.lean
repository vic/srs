/-
L2.3b: protocol ops in the GENERATED checker. `step` (s1/check.srs) accepts op o on cap c only when o has a
transition from c's current state in Γ, and then moves c to the target state (= Model.step). So the impl
rejects double free, alloc after free, and every order or count break of a protocol.
-/
import Srs.Proofs.Live

set_option autoImplicit false

namespace Srs.Proofs
open Srs.Impl Srs.Rt

theorem lkp_isNode (k : «Kind») (hk : k ≠ .«TEof») (s : ByteArray) :
    ∀ (l : List «Node») (h : «Node»), lkp k s l = some h → isNode h = true
  | [], _, hl => by simp [lkp] at hl
  | x :: t, h, hl => by
    unfold lkp at hl
    split at hl
    · rename_i hm
      simp only [Option.some.injEq] at hl
      subst hl
      cases x with
      | «NoNode» => exact absurd hm.1.symm (by simpa [kd] using hk)
      | «Node» => rfl
    · exact lkp_isNode k hk s t h hl

/-- the op decl `opName` of protocol `proto` -/
def opS (ds : «Nodes») (proto opName : ByteArray) : Option «Node» :=
  lkp .«DOp» opName (toL (ks (hdN (dropN 3 (ks ((lkp .«DProto» proto (toL ds)).getD .«NoNode»))))))
/-- cap's state in Γ -/
def stS (gam : «Nodes») (cap : ByteArray) : ByteArray := t2 ((lkp .«GState» cap (toL gam)).getD .«NoNode»)
/-- the transition of op from state s -/
def trS (op : «Node») (s : ByteArray) : Option «Node» := lkp .«DTrans» s (toL (ks (hdN (dropN 2 (ks op)))))

theorem getD_none {l : List «Node»} {k : «Kind»} {s : ByteArray} (h : lkp k s l = none) :
    (lkp k s l).getD .«NoNode» = .«NoNode» := by simp [h]

/-- the generated `step`: accepted ⟹ the op exists, a transition from the cap's current state exists, and Γ
after = the cap moved to the transition's target -/
theorem step_ok (ds gam : «Nodes») (cap proto opName : ByteArray) (line : Int) (g' : «Nodes»)
    (h : «step» ds gam cap proto opName line = some g') :
    ∃ op tr, opS ds proto opName = some op ∧ trS op (stS gam cap) = some tr ∧
      g' = ofL (repl (.«Node» .«GState» cap (t2 tr) 0 0 .«NNil») false (toL gam)) := by
  unfold «step» at h
  simp only [find_spec, kid_spec, kids_eq, found_eq, «state», text2_t2, bind, Option.bind] at h
  cases hop : lkp .«DOp» opName (toL (ks (hdN (dropN 3 (ks ((lkp .«DProto» proto (toL ds)).getD .«NoNode»))))))
    with
  | none => simp [hop, isNode, err_none] at h
  | some op =>
    have hopn := lkp_isNode .«DOp» (by decide) opName _ op hop
    cases htr : lkp .«DTrans» (t2 ((lkp .«GState» cap (toL gam)).getD .«NoNode»)) (toL (ks (hdN (dropN 2 (ks op)))))
      with
    | none =>
      simp [hop, htr, hopn, rt_eprint, rt_eprint_i64, rt_exit, pure] at h
      simp [isNode] at h
    | some tr =>
      have htrn := lkp_isNode .«DTrans» (by decide) _ _ tr htr
      simp [hop, htr, hopn, htrn, setG_spec] at h
      exact ⟨op, tr, hop, htr, h.symm⟩

/-- the generated `chkMethod` (cap.op(args)): the Γ it returns is the `step` of the op on that cap, from the Γ
after the args -/
theorem chkMethod_step (ds env gam0 : «Nodes») (e : «Node») (tg : «TG»)
    (h : «chkMethod» ds env gam0 e = some tg) :
    ∃ gam proto line ty g', «step» ds gam (t1 e) proto (t2 e) line = some g' ∧ tg = .«TG» ty g' := by
  unfold «chkMethod» at h
  simp [bind, Option.bind_eq_some_iff, err_none, pure, text_t1, text2_t2] at h
  obtain ⟨line, -, b, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, -, gam, -, ty, -, g', hs, rfl⟩ := h
  exact ⟨gam, _, line, ty, g', hs, rfl⟩

/-- headline (impl): the generated checker accepts `cap.op(args)` only along a protocol transition from the
cap's current state, and the Γ after is the cap moved to the transition's target -/
theorem chkMethod_transition (ds env gam0 : «Nodes») (e : «Node») (tg : «TG»)
    (h : «chkMethod» ds env gam0 e = some tg) :
    ∃ gam proto op tr ty, opS ds proto (t2 e) = some op ∧ trS op (stS gam (t1 e)) = some tr ∧
      tg = .«TG» ty (ofL (repl (.«Node» .«GState» (t1 e) (t2 tr) 0 0 .«NNil») false (toL gam))) := by
  obtain ⟨gam, proto, line, ty, g', hs, rfl⟩ := chkMethod_step ds env gam0 e tg h
  obtain ⟨op, tr, hop, htr, rfl⟩ := step_ok ds gam (t1 e) proto (t2 e) line g' hs
  exact ⟨gam, proto, op, tr, ty, hop, htr, rfl⟩

end Srs.Proofs
