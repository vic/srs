// vic-hm63 P0 (vic/c/multishot-design.md): NonDet by selective defunctionalized CPS, written by hand as the emitter will
// write it. Each resume point of the body is one frame case; a frame is immutable and lives in one arena freed at the
// end of the handle; choose resumes the same frame twice (multi-shot, no copy); fail does not resume.
// Body: x <- pick 1..3; y <- pick 1..3; x + y == 4.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// the arena of one handle: frames are bumped, freed once
typedef struct {
  char *buf;
  size_t used, cap;
} Arena;

static void *alloc(Arena *a, size_t n) {
  if (a->used + n > a->cap) return NULL;
  void *p = a->buf + a->used;
  a->used += n;
  return p;
}

// the resume points of body (pc) and of pick (its own loop state)
typedef enum { K_AFTER_X, K_AFTER_Y } Pc;

typedef struct Frame {
  Pc pc;
  int x;  // live after the first pick
} Frame;

// a pick in flight: the frame to resume with its value, and the loop state of pick
typedef struct Pick {
  const Frame *k;
  int i, hi;
} Pick;

static void resume(Arena *a, const Frame *k, int v);

// pick lo..hi in CPS: choose at value i resumes k with i (true) and continues the loop (false); the last value is not
// a choice. choose is the handler op: it calls both branches, the same immutable k each time
static void pick(Arena *a, const Pick *p) {
  if (p->i == p->hi) {
    resume(a, p->k, p->hi);
    return;
  }
  resume(a, p->k, p->i);  // choose -> true
  Pick *q = alloc(a, sizeof(Pick));
  if (!q) abort();
  *q = (Pick){p->k, p->i + 1, p->hi};
  pick(a, q);  // choose -> false
}

static void pick_k(Arena *a, const Frame *k, int lo, int hi) {
  Pick *p = alloc(a, sizeof(Pick));
  if (!p) abort();
  *p = (Pick){k, lo, hi};
  pick(a, p);
}

// the body after each resume point; fail = return without resuming anything
static void resume(Arena *a, const Frame *k, int v) {
  switch (k->pc) {
    case K_AFTER_X: {
      Frame *k2 = alloc(a, sizeof(Frame));
      if (!k2) abort();
      *k2 = (Frame){K_AFTER_Y, v};
      pick_k(a, k2, 1, 3);
      return;
    }
    case K_AFTER_Y:
      if (k->x + v != 4) return;  // fail
      printf("(%d,%d)\n", k->x, v);
      return;
  }
}

int main(void) {
  Arena a = {malloc(1 << 16), 0, 1 << 16};
  if (!a.buf) return 1;
  Frame *k0 = alloc(&a, sizeof(Frame));
  *k0 = (Frame){K_AFTER_X, 0};
  pick_k(&a, k0, 1, 3);
  free(a.buf);  // the handle ends: every frame at once
  return 0;
}
