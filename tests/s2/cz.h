// test probe (tests/run.sh, mem census): a program's C, rewritten by sed so each box allocation names its case,
// counts the boxes of each case and prints "CZ <case> <count>" to stderr at exit. Not part of any program srs emits.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { const char* n; long long c; } cz_row;
static cz_row cz_t[4096];
static int cz_armed;
static void cz_dump(void) {
  for (int i = 0; i < 4096; i++) if (cz_t[i].n) fprintf(stderr, "CZ %s %lld\n", cz_t[i].n, cz_t[i].c);
}
static inline void cz(const char* n) {
  if (!cz_armed) { cz_armed = 1; atexit(cz_dump); }
  unsigned long h = 5381;
  for (const char* p = n; *p; p++) h = h * 33 + (unsigned char)*p;
  h &= 4095;
  while (cz_t[h].n && strcmp(cz_t[h].n, n) != 0) h = (h + 1) & 4095;
  cz_t[h].n = n; cz_t[h].c++;
}
#define CZA(n, c, s) (cz(n), srs_alloc(c, s))
