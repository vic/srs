// srs runtime: C ABI services bound by `extern def` in lib/prelude.srs.
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const uint8_t* p; int64_t n; } srs_str;

static int g_argc;
static char** g_argv;

void rt_init(int argc, char** argv) { g_argc = argc; g_argv = argv; }

int64_t rt_argc(void) { return g_argc; }
srs_str rt_arg(int64_t i) {
  if (i < 0 || i >= g_argc) return (srs_str){(const uint8_t*)"", 0};
  return (srs_str){(const uint8_t*)g_argv[i], (int64_t)strlen(g_argv[i])};
}

// Arena allocator: linked chunks, bump allocation, freed as a whole.
typedef struct chunk { struct chunk* next; size_t used, cap; } chunk;
typedef struct { chunk* head; } arena;
enum { CHUNK = 1 << 20 };

void* rt_arena_new(void) { return calloc(1, sizeof(arena)); }
void* rt_arena_alloc(void* self, int64_t size) {
  arena* a = self;
  size_t n = ((size_t)size + 15) & ~(size_t)15;
  if (!a->head || a->head->used + n > a->head->cap) {
    size_t cap = n > CHUNK ? n : CHUNK;
    chunk* c = malloc(sizeof(chunk) + cap);
    if (!c) { fputs("srs: out of memory\n", stderr); exit(70); }
    c->next = a->head; c->used = 0; c->cap = cap; a->head = c;
  }
  void* p = (char*)(a->head + 1) + a->head->used;
  a->head->used += n;
  return p;
}
int64_t rt_arena_free(void* self) {
  arena* a = self;
  for (chunk* c = a->head; c;) { chunk* n = c->next; free(c); c = n; }
  free(a);
  return 0;
}

// Malloc allocator: every alloc is a separate block, tracked for free.
typedef struct block { struct block* next; } block;
typedef struct { block* head; int64_t count; } heap;
void* rt_heap_new(void) { return calloc(1, sizeof(heap)); }
void* rt_heap_alloc(void* self, int64_t size) {
  heap* h = self;
  block* b = malloc(sizeof(block) + (size_t)size);
  if (!b) { fputs("srs: out of memory\n", stderr); exit(70); }
  b->next = h->head; h->head = b; h->count++;
  return b + 1;
}
int64_t rt_heap_free(void* self) {
  heap* h = self;
  for (block* b = h->head; b;) { block* n = b->next; free(b); b = n; }
  free(h);
  return 0;
}

srs_str rt_read_file(srs_str path) {
  char name[4096];
  if (path.n >= (int64_t)sizeof name) return (srs_str){(const uint8_t*)"", -1};
  memcpy(name, path.p, (size_t)path.n); name[path.n] = 0;
  FILE* f = fopen(name, "rb");
  if (!f) return (srs_str){(const uint8_t*)"", -1};
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  uint8_t* buf = malloc((size_t)n + 1);
  if (!buf || fread(buf, 1, (size_t)n, f) != (size_t)n) { fclose(f); return (srs_str){(const uint8_t*)"", -1}; }
  fclose(f);
  return (srs_str){buf, n}; // program-lifetime: never freed
}

int64_t rt_print(srs_str s) { fwrite(s.p, 1, (size_t)s.n, stdout); return 0; }
int64_t rt_eprint(srs_str s) { fwrite(s.p, 1, (size_t)s.n, stderr); return 0; }
int64_t rt_print_i64(int64_t v) { printf("%lld", (long long)v); return 0; }
int64_t rt_eprint_i64(int64_t v) { fprintf(stderr, "%lld", (long long)v); return 0; }
int64_t rt_print_char(int64_t c) { putchar((int)c); return 0; }
int64_t rt_str_len(srs_str s) { return s.n; }
int64_t rt_str_at(srs_str s, int64_t i) { return (i >= 0 && i < s.n) ? s.p[i] : -1; }
srs_str rt_str_slice(srs_str s, int64_t b, int64_t e) {
  if (b < 0) b = 0;
  if (e > s.n) e = s.n;
  if (e < b) e = b;
  return (srs_str){s.p + b, e - b};
}
bool rt_str_eq(srs_str a, srs_str b) { return a.n == b.n && memcmp(a.p, b.p, (size_t)a.n) == 0; }
int64_t rt_exit(int64_t code) { fflush(stdout); exit((int)code); }
