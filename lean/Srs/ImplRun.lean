/-
Backend oracle (L1): the generated Lean S1 (Impl, from s1/*.srs) runs the srs pipeline lex, parse, check on every
test program and gives the C-compiled S1 verdict: tests/*.srs accepted, tests/neg/*.srs rejected (rt_exit = none).
A mismatch fails the build: the Lean backend changed the meaning of the program.
-/
import Srs.Impl.S1

open Srs.Impl

def implAccepts (srcs : List String) : IO Bool := do
  let mut ds := Nodes.NNil
  for p in srcs do
    let src := (← IO.FS.readBinFile p)
    match lex src >>= parseFile >>= append ds with
    | some x => ds := x
    | none => return false
  -- errors are data (vic-ngq): a checked program with a mark (XIllTyped) is rejected
  match check ds with
  | some ds2 =>
    match illTypedIn ds2 with
    | some Nodes.NNil => return (mkDecls ds2 >>= mono).isSome
    | _ => return false
  | none => return false

def checkVerdicts : IO Unit := do
  let libs := ["../lib/prelude.srs", "../lib/kanren.srs", "../lib/datalog.srs", "../tests/list.lib", "../tests/file.lib"]
  let dir (d : String) : IO (List String) := do
    let es ← System.FilePath.readDir d
    return (es.toList.map (·.path.toString)).filter (·.endsWith ".srs") |>.mergeSort
  let pos ← dir "../tests"
  let neg ← dir "../tests/neg"
  if pos.isEmpty || neg.isEmpty then throw (IO.userError "no test programs found")
  for p in pos do
    unless (← implAccepts (libs ++ [p])) do throw (IO.userError s!"Impl rejects {p}, S1 accepts it")
  for p in neg do
    if (← implAccepts (libs ++ [p])) then throw (IO.userError s!"Impl accepts {p}, S1 rejects it")
  IO.println s!"Impl verdicts = S1: {pos.length} pass, {neg.length} neg"

#eval checkVerdicts
