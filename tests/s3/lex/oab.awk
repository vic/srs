# pass 1 (dump): tokens; pass 2 (od): bytes. O-a: order/no overlap/in range/coverage; O-b: gaps are ws or // comments
NR==FNR { if ($1=="diag") next; o=$2+0; l=$3+0
  if (o<pe) { print "FAIL O-a overlap/disorder at token " nt " off=" o " prevend=" pe; bad=1 }
  for (k=o;k<o+l;k++) cov[k]=1
  tb+=l; pe=o+l; nt++; next }
{ b=$1+0; k=FNR-1; sz=FNR
  if (cov[k]) { if (inc||sl) { if(!reported++) print "FAIL O-b token byte inside comment/after lone slash at " k; bad=1 } ; next }
  gb++
  if (inc) { if (b==10) inc=0; next }
  if (sl) { if (b==47) { inc=1; sl=0; next } else { if(!reported++) print "FAIL O-b lone slash gap at " (k-1); bad=1; sl=0 } }
  if (b==32||b==10||b==13) next
  if (keep && b==47) { if(!reported++) print "FAIL O-b comment bytes in a gap (keep mode) at " k; bad=1; next }
  if (b==47) { sl=1; next }
  if(!reported++) print "FAIL O-b gap byte " b " at " k; bad=1 }
END { if (sl) { print "FAIL O-b trailing lone slash"; bad=1 }
  if (pe>sz) { print "FAIL O-a last end " pe " > size " sz; bad=1 }
  if (tb+gb!=sz) { print "FAIL O-a tokbytes+gapbytes=" tb+gb " != size " sz; bad=1 }
  printf "%s tokens=%d size=%d tokbytes=%d gapbytes=%d\n", bad?"FAIL":"OK", nt, sz, tb, gb; exit bad }
