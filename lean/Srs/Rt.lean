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
def rt_str_eq (a b : ByteArray) : Option Bool := pure (a.data == b.data)

end Srs.Rt
