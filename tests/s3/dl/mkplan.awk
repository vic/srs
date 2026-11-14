# shortcut: planner + symbol interning in awk until DL-1b moves them into srs (s3 typed relation library).
# mkplan.awk: DL-1 loader/planner. usage: gawk -v DL=mem2.dl -v FACTS=dir -v OUT=dir [-v MUT=neg|alldelta] -f mkplan.awk
# writes OUT/in.txt (plan ints + EDB facts as U32 ids), OUT/sym.txt (id TAB text), OUT/rels.txt (id name arity types).
# plan = executor input: strata, variants with join order, per-column tags, index choice. the engine (s3/dl.srs) only executes it.
function die(m) { print "mkplan: " m > "/dev/stderr"; exit 1 }
function nm(s) { gsub(/[ \t]/, "", s); return s }
function arity_of(r) { return ar[r] }
function termtag(t) { if (t ~ /^[0-9]+$/) return "c"; if (t == "_") return "w"; return "v" }

# bound/slot helpers for one variant being planned
function place(ai,   r, k, t, tg, sp, mask, id, key) {
  r = brel[cur, ai]; sp = ""; mask = 0
  for (k = 1; k <= ar[r]; k++) {
    t = bt[cur, ai, k]; tg = termtag(t)
    if (tg == "c") { sp = sp " 0 " t; mask += 2^(k-1) }
    else if (tg == "w") die("wildcard unsupported")
    else if (t in bound) { sp = sp " 1 " slot[t]; mask += 2^(k-1) }
    else if (t in seen_here) { sp = sp " 5 " slot[t] }
    else { if (!(t in slot)) { slot[t] = nslot++ } seen_here[t] = 1; sp = sp " 2 " slot[t] }
  }
  for (t in seen_here) { bound[t] = 1 }
  delete seen_here
  return mask "|" sp
}
function negready(ai,   k, t) {
  for (k = 1; k <= ar[brel[cur, ai]]; k++) { t = bt[cur, ai, k]; if (termtag(t) == "v" && !(t in bound)) return 0 }
  return 1
}
function idxid(r, mask,   key) {
  if (mask == full[r]) return r
  key = r "," mask
  if (!(key in idxmap)) { idxmap[key] = nidx; idxrel[nidx] = r; idxmask[nidx] = mask; nidx++ }
  return idxmap[key]
}
function boundcount(ai,   k, t, c) {
  c = 0
  for (k = 1; k <= ar[brel[cur, ai]]; k++) { t = bt[cur, ai, k]; if (termtag(t) == "c" || (t in bound)) c++ }
  return c
}
# plan rule `cur`, driver atom d (positive); returns variant text in vtxt
function plan(d, kind,   n, i, j, best, bc, c, out, p, m, na, hs, k, t, sp, ids, parts, atomtxt) {
  delete bound; delete slot; delete placed; delete seen_here; nslot = 0
  n = nb[cur]; na = 0; atomtxt = ""
  # driver
  p = place(d); split(p, parts, "|")
  atomtxt = atomtxt " 0 " brel[cur, d] " -1" parts[2]; na++; placed[d] = 1
  # greedy
  while (1) {
    # negatives that are ready
    for (i = 1; i <= n; i++) if (!(i in placed) && bneg[cur, i] && negready(i)) {
      p = place(i); split(p, parts, "|")
      atomtxt = atomtxt " 1 " brel[cur, i] " " brel[cur, i] parts[2]; na++; placed[i] = 1
    }
    best = 0; bc = -1
    for (i = 1; i <= n; i++) if (!(i in placed) && !bneg[cur, i]) { c = boundcount(i); if (c > bc) { bc = c; best = i } }
    if (best == 0) break
    p = place(best); split(p, parts, "|"); m = parts[1] + 0
    atomtxt = atomtxt " 0 " brel[cur, best] " " idxid(brel[cur, best], m) parts[2]; na++; placed[best] = 1
  }
  for (i = 1; i <= n; i++) if (!(i in placed)) die("unsafe negation in rule " cur)
  hs = ""
  for (k = 1; k <= ar[hrel[cur]]; k++) {
    t = ht[cur, k]
    if (termtag(t) == "c") hs = hs " 0 " t
    else if (t in slot) hs = hs " 1 " slot[t]
    else die("unbound head var in rule " cur)
  }
  if (nslot > maxslot) maxslot = nslot
  return kind " " hrel[cur] hs " " na atomtxt
}

BEGIN {
  FS = "\n"
  nr = 0; nru = 0; nidx = 0
  while ((getline line < DL) > 0) {
    if (line ~ /^\.decl /) {
      s = line; sub(/^\.decl /, "", s); name = s; sub(/\(.*/, "", name)
      args = s; sub(/^[^(]*\(/, "", args); sub(/\)[ \t]*$/, "", args)
      na = split(args, A, ","); ty = ""
      for (k = 1; k <= na; k++) { split(A[k], B2, ":"); ty = ty (nm(B2[2]) == "symbol" ? "s" : "n") }
      rid[name] = nr; rname[nr] = name; ar[nr] = na; rty[nr] = ty; full[nr] = 2^na - 1; nr++
    } else if (line ~ /^\.input /) {
      s = line; sub(/^\.input /, "", s); sub(/\(.*/, "", s); isin[rid[s]] = 1
    } else if (line ~ /:-/) {
      sub(/\.[ \t]*$/, "", line)
      split(line, HB, / :- /)
      h = HB[1]; hn = h; sub(/\(.*/, "", hn); ha = h; sub(/^[^(]*\(/, "", ha); sub(/\)$/, "", ha)
      if (!(hn in rid)) die("undeclared head " hn)
      cur = nru; hrel[cur] = rid[hn]
      k2 = split(ha, T, ","); if (k2 != ar[rid[hn]]) die("head arity " hn)
      for (k = 1; k <= k2; k++) ht[cur, k] = nm(T[k])
      body = HB[2]
      if (body ~ /!=|<=|>=|[^!]=/) die("comparison literal unsupported: " line)
      nb[cur] = 0
      while (match(body, /!?[A-Za-z_][A-Za-z0-9_]*\([^)]*\)/)) {
        at = substr(body, RSTART, RLENGTH); body = substr(body, RSTART + RLENGTH)
        ng = (substr(at, 1, 1) == "!"); if (ng) at = substr(at, 2)
        an = at; sub(/\(.*/, "", an); aa = at; sub(/^[^(]*\(/, "", aa); sub(/\)$/, "", aa)
        if (!(an in rid)) die("undeclared body " an)
        i = ++nb[cur]; brel[cur, i] = rid[an]; bneg[cur, i] = ng
        k2 = split(aa, T, ","); if (k2 != ar[rid[an]]) die("body arity " an)
        for (k = 1; k <= k2; k++) bt[cur, i, k] = nm(T[k])
      }
      nru++
    }
  }
  # strata: s[h] >= s[p] (+1 for negation; MUT=neg drops the +1)
  for (r = 0; r < nr; r++) st[r] = 0
  do {
    ch = 0
    for (u = 0; u < nru; u++) for (i = 1; i <= nb[u]; i++) {
      need = st[brel[u, i]] + ((bneg[u, i] && MUT != "neg") ? 1 : 0)
      if (st[hrel[u]] < need) { st[hrel[u]] = need; ch = 1 }
    }
  } while (ch)
  ns = 0; for (r = 0; r < nr; r++) if (st[r] + 1 > ns) ns = st[r] + 1
  # fact counts (estimates for the driver choice)
  for (r = 0; r < nr; r++) { cnt[r] = 0; est[r] = 1000000 }
  for (r = 0; r < nr; r++) if (isin[r]) {
    f = FACTS "/" rname[r] ".facts"; n = 0
    while ((getline l < f) > 0) n++
    close(f); cnt[r] = n; est[r] = n
  }
  # index ids: 0..nr-1 = the full-column index of each relation (dedup, negation), then one per (relation, bound set)
  for (r = 0; r < nr; r++) { idxrel[r] = r; idxmask[r] = full[r] }
  nidx = nr
  # variants per stratum
  maxslot = 0
  for (s = 0; s < ns; s++) nv[s] = 0
  for (u = 0; u < nru; u++) {
    cur = u; s = st[hrel[u]]; rec = 0
    for (i = 1; i <= nb[u]; i++) if (!bneg[u, i] && st[brel[u, i]] == s) rec++
    if (rec == 0 || MUT == "alldelta") {
      best = 0; be = 1e18
      for (i = 1; i <= nb[u]; i++) if (!bneg[u, i] && est[brel[u, i]] < be) { be = est[brel[u, i]]; best = i }
      if (best == 0) die("rule without positive atom")
      vt[s, nv[s]++] = plan(best, 0)
    }
    if (rec > 0) for (i = 1; i <= nb[u]; i++) if (!bneg[u, i] && st[brel[u, i]] == s) vt[s, nv[s]++] = plan(i, 1)
  }
  # symbols: interned at load, one global id space
  nsym = 0
  for (r = 0; r < nr; r++) if (isin[r]) {
    f = FACTS "/" rname[r] ".facts"; fl[r] = ""
    nl = 0
    while ((getline l < f) > 0) {
      nf = split(l, C, "\t")
      if (nf != ar[r]) die("fact arity " rname[r])
      row = ""
      for (k = 1; k <= nf; k++) {
        if (substr(rty[r], k, 1) == "s") { if (!(C[k] in sid)) { sid[C[k]] = nsym; stx[nsym] = C[k]; nsym++ } v = sid[C[k]] } else v = C[k]
        row = row (k > 1 ? " " : "") v
      }
      rows[r, nl++] = row
    }
    close(f)
  }
  # plan text
  ptxt = ""
  for (r = 0; r < nr; r++) ptxt = ptxt " " ar[r]
  ptxt = ptxt "\n"
  nidx0 = nidx
  # idx list
  tmp = ""; for (x = 0; x < nidx; x++) tmp = tmp " " idxrel[x] " " idxmask[x]
  nint = 0
  body2 = ""
  for (s = 0; s < ns; s++) {
    body2 = body2 nv[s] "\n"
    for (j = 0; j < nv[s]; j++) body2 = body2 vt[s, j] "\n"
  }
  # header: NR NI NS MAXSLOT then arities, idx pairs, strata
  pn = split(substr(ptxt, 2, length(ptxt) - 2) " " tmp " " body2, PNA, /[ \n]+/)
  if (PNA[pn] == "") pn--
  hdr = pn " " nr " " nidx " " ns " " maxslot
  out = OUT "/in.txt"
  print hdr > out
  print substr(ptxt, 2, length(ptxt) - 2) > out
  print substr(tmp, 2) > out
  printf "%s", body2 > out
  for (r = 0; r < nr; r++) {
    print cnt[r] > out
    for (j = 0; j < cnt[r]; j++) print rows[r, j] > out
  }
  close(out)
  for (j = 0; j < nsym; j++) print j "\t" stx[j] > (OUT "/sym.txt")
  close(OUT "/sym.txt")
  for (r = 0; r < nr; r++) print r " " rname[r] " " ar[r] " " rty[r] " " st[r] > (OUT "/rels.txt")
  close(OUT "/rels.txt")
  print "nr=" nr " rules=" nru " strata=" ns " idx=" nidx " maxslot=" maxslot " syms=" nsym > "/dev/stderr"
}
