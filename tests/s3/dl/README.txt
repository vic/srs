tests/s3/dl: oracle for the s3 Datalog engine (s3/dl.srs, s3/dlmain.srs).

What is here
  mem2.dl            the Mem analysis rules (65 relations, 66 rules) of s2c on its own Y1 self-compile, in Souffle syntax.
  verdict.rels       the 20 relations that Mem.report reads (D.tuples): the ones that decide the analysis result.
  mkplan.awk         planner + loader. shortcut: planner in awk until DL-1b moves it into srs. Reads mem2.dl + the facts,
                     emits the integer plan the engine executes (strata, join order, index choice, symbol interning).
  unmap.awk          maps the engine's id output back to text, one .csv per relation.
  dl-run.sh          the oracle: plan, run the engine binary, unmap, compare all 65 relations against the baseline.
                     bash tests/s3/dl/dl-run.sh <engine-binary>   (from the repo root; last line PASS dl-engine / FAIL ...)
  souffle-oracle.sh  reference workbench: runs Souffle on a .dl and compares the verdict relations (slow: C++ build ~65 s).
  dump-hook.srs.txt  the srs code that dumps rules and facts of the Mem solve (see "How the facts are regenerated").

Data (not committed: 300,030 facts, 837,862 rows; default location $HOME/.cache/srs3/dl, override with S3_DL_DATA)
  facts/*.facts      35 tab-separated files, no header, one per input relation (symbols as text, numbers as decimals).
  baseline/*.csv     65 files, Souffle's output rows for every relation (tab separated).

How the facts are regenerated (the X1 dump recipe; main at the time: 5c6980fd)
  1. Take a COPY of s2/*.srs, lib/prelude.srs and s2c/main.srs in a scratch dir. Never edit the repo files.
  2. In the copy, replace the single D.solve call of Mem.report (s2/mem.srs, `D.solve(Coll.revOnto(...))`, the only
     solve reached by the --mem path in s2c/main.srs) by a wrapper that prints, between markers, every rule as a Souffle
     rule (`head(v0, v1) :- body, !neg.`, variables v<n>, symbols as quoted text) and every fact as `REL<TAB>v1<TAB>v2...`,
     then continues normally. The wrapper code is dump-hook.srs.txt.
  3. Compile the patched copy with the seed compiler, run `<patched> --mem lib/prelude.srs s2/*.srs s2c/main.srs`
     from the repo root (the ORIGINAL sources are the input), capture stdout.
  4. Split with awk: one facts/<REL>.facts per relation; mem2.dl = `.decl` per relation (column type symbol or number from
     the first fact of each relation), `.input REL(IO=file, filename="REL.facts", delimiter="\t")` per relation with facts,
     `.output REL` per derived relation, then the rules 1:1.
  5. baseline: `souffle -j1 mem2.dl -F facts -D baseline` (Souffle 2.5; `nix-shell -p souffle`). Check that the 65
     relation row counts equal the srs engine's own counts (D.tuples on the Solved model): 65/65, 837,862 rows.
  The recipe is valid for the s2c source at the commit above. A newer s2c changes the rules and the counts: regenerate
  mem2.dl, facts and baseline together.
