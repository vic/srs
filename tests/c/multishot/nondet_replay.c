// vic-hm63 P0 (vic/c/multishot-design.md): NonDet by replay. The handler reruns the body from the handle point with a
// log of choices; fail is a longjmp back to the handle point. Body: x <- pick 1..3; y <- pick 1..3; x + y == 4.
#include <setjmp.h>
#include <stdio.h>

enum { MAX = 64 };

typedef struct {
  jmp_buf top;
  int log[MAX];
  int len;
  int pos;
} NonDet;

// choose: replay the logged choice, else take the first branch (1) and log it
static int choose(NonDet *h) {
  if (h->pos < h->len) return h->log[h->pos++];
  h->log[h->len++] = 1;
  h->pos++;
  return 1;
}

static void fail(NonDet *h) { longjmp(h->top, 1); }

// pick lo..hi: one choose per value but the last
static int pick(NonDet *h, int lo, int hi) {
  for (int i = lo; i < hi; i++)
    if (choose(h)) return i;
  return hi;
}

static void body(NonDet *h) {
  int x = pick(h, 1, 3);
  int y = pick(h, 1, 3);
  if (x + y != 4) fail(h);
  printf("(%d,%d)\n", x, y);
}

// the next log: drop trailing 0s, flip the last 1 to 0; none left: done
static int next(NonDet *h) {
  while (h->len > 0 && h->log[h->len - 1] == 0) h->len--;
  if (h->len == 0) return 0;
  h->log[h->len - 1] = 0;
  return 1;
}

int main(void) {
  NonDet h = {.len = 0};
  do {
    h.pos = 0;
    if (setjmp(h.top) == 0) body(&h);
    h.len = h.pos;  // a run logs only up to where it stopped
  } while (next(&h));
  return 0;
}
