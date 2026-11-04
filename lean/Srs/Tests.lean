/-
The Lean checker agrees with S1 on the effect tests of tests/ and tests/neg/ (same verdict).
caps 0, 1 = Region (lib/prelude.srs); cap 2 = CFile (tests/file.lib). vars 0 = xs, 1 = ys.
-/
import Srs.Model

namespace Srs.Tests
open Stmt Expr

/-- Region: Open 0, Freed 1. alloc 0 : Open → Open, free 1 : Open → Freed. drop free -/
def region : Proto where
  start := 0
  isEnd := (· == 1)
  trans := fun o s => if o == 0 && s == 0 then some 0 else if o == 1 && s == 0 then some 1 else none
  drop := some 1

/-- CFile: Opened 0, Read1 1, Read2 2, Closed 3. read 0 : Opened → Read1, Read1 → Read2.
close 1 : Read1 → Closed, Read2 → Closed. no drop -/
def file : Proto where
  start := 0
  isEnd := (· == 3)
  trans := fun o s =>
    if o == 0 && s == 0 then some 1 else if o == 0 && s == 1 then some 2
    else if o == 1 && (s == 1 || s == 2) then some 3 else none
  drop := none

def P : Nat → Proto := fun c => if c == 2 then file else region

def ok (s : Stmt) : Bool := (check P 16 s ⟨[], []⟩).isSome

def seqs : List Stmt → Stmt
  | [] => skip
  | [s] => s
  | s :: ss => seq s (seqs ss)

-- pass programs
#guard ok (hdl 0 (seqs [asg 0 (pair (alloc 0 0) (alloc 0 0)), use (rd 0), op 0 1])) -- region_ok
#guard ok (hdl 2 (seqs [op 2 0, op 2 1])) -- file_ok READ{1}
#guard ok (hdl 2 (seqs [op 2 0, op 2 0, op 2 1])) -- file_ok READ{2}
#guard ok (hdl 0 (hdl 1 (seqs [asg 0 (alloc 0 0), asg 0 (alloc 1 0), op 0 1, use (rd 0)]))) -- var_ok
#guard ok (hdl 0 (seqs [asg 0 (alloc 0 0), use (rd 0)])) -- drop free at scope end
-- neg programs
#guard !ok (hdl 0 (seqs [asg 0 (alloc 0 0), op 0 1, use (rd 0)])) -- use_after_free
#guard !ok (hdl 0 (seqs [op 0 1, op 0 1])) -- double_free
#guard !ok (hdl 0 (seqs [op 0 1, asg 0 (alloc 0 0)])) -- alloc_after_free
#guard !ok (hdl 2 (seqs [op 2 0, op 2 0, op 2 0, op 2 1])) -- read_three
#guard !ok (hdl 2 (op 2 1)) -- close_no_read
#guard !ok (hdl 2 (op 2 0)) -- missing_close
#guard !ok (hdl 2 (seqs [ite (op 2 0) skip, op 2 1])) -- branch_state
#guard !ok (hdl 2 (seqs [loop (op 2 0), op 2 1])) -- loop_state
#guard !ok (hdl 0 (seqs [op 0 1, asg 0 (alloc 0 0)])) -- call_freed (inlined)
#guard !ok (hdl 0 (hdl 1 (seqs [asg 0 (alloc 1 0), asg 0 (alloc 0 0), op 0 1, use (rd 0)]))) -- var_assign
#guard !ok (hdl 0 (hdl 1 (seqs [asg 0 (alloc 1 0), ite (asg 0 (alloc 0 0)) skip, op 0 1, use (rd 0)]))) -- var_branch
#guard !ok (hdl 0 (hdl 1 (seqs [asg 0 (alloc 1 0), asg 1 (alloc 1 0),
  loop (seq (asg 1 (rd 0)) (asg 0 (alloc 0 0))), op 0 1, use (rd 1)]))) -- var_loop
#guard !ok (seqs [hdl 0 (asg 0 (alloc 0 0)), use (rd 0)]) -- escape: value outlives its region

end Srs.Tests
