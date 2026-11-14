# unmap.awk: engine output (@id, rows of ids) -> OUT/name.csv with symbols as text. -v P=plan dir -v OUT=dir
BEGIN {
  while ((getline l < (P "/sym.txt")) > 0) { i = index(l, "\t"); sym[substr(l, 1, i - 1)] = substr(l, i + 1) }
  while ((getline l < (P "/rels.txt")) > 0) { split(l, F, " "); rn[F[1]] = F[2]; rt[F[1]] = F[4]; ra[F[1]] = F[3] }
  FS = "\t"; cur = ""
}
/^@/ {
  if (cur != "") close(cur)
  id = substr($0, 2); cur = OUT "/" rn[id] ".csv"; ty = rt[id]; printf "" > cur; next
}
{
  line = ""
  for (k = 1; k <= NF; k++) { v = $k; if (substr(ty, k, 1) == "s") v = sym[v]; line = line (k > 1 ? "\t" : "") v }
  print line > cur
}
