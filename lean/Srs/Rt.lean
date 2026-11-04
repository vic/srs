/-
The C runtime (rt/srs_rt.c) as Lean: the externs the generated Impl calls. TRUSTED BASE (vic/c/lean-backend.md).
Str = ByteArray (C ptr+len). rt_exit = none (the run stops). Output is not modeled: print/eprint = pure ().
I64 = Int: ASSUMPTION no overflow. Out-of-range rt_str_at is UB in C; here it reads 0.
-/
set_option autoImplicit false

namespace Srs.Rt

def rt_print (_ : ByteArray) : Option Unit := pure ()
def rt_eprint (_ : ByteArray) : Option Unit := pure ()
def rt_print_i64 (_ : Int) : Option Unit := pure ()
def rt_eprint_i64 (_ : Int) : Option Unit := pure ()
def rt_exit (_ : Int) : Option Unit := none
def rt_str_len (s : ByteArray) : Option Int := pure s.size
def rt_str_at (s : ByteArray) (i : Int) : Option Int := pure (s.get! i.toNat).toNat
def rt_str_slice (s : ByteArray) (b e : Int) : Option ByteArray := pure (s.extract b.toNat e.toNat)
def rt_str_eq (a b : ByteArray) : Option Bool := pure (decide (a = b))

-- pure versions, for specs and contracts (`spec def`, requires, ensures, invariant)
namespace P
def rt_str_len (s : ByteArray) : Int := s.size
def rt_str_at (s : ByteArray) (i : Int) : Int := (s.get! i.toNat).toNat
def rt_str_slice (s : ByteArray) (b e : Int) : ByteArray := s.extract b.toNat e.toNat
def rt_str_eq (a b : ByteArray) : Bool := decide (a = b)
end P

/-- rt_str_eq = the C byte compare (same length, same bytes): ByteArray is one field, `data` -/
theorem rt_str_eq_bytes (a b : ByteArray) : P.rt_str_eq a b = (a.data == b.data) := by
  by_cases h : a = b <;> simp [P.rt_str_eq, h]
  intro h2; apply h; cases a; cases b; simp_all

end Srs.Rt
