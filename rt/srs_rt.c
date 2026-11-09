// srs runtime: C ABI services bound by `extern def` in lib/prelude.srs.
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

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

// ── the store (vic-uw3 H2): $SRS_STORE, else $HOME/.srs/store; an entry = file <dir>/<a>.<b>.<c>.<d> (hash lanes)
srs_str rt_store_dir(void) {
  static char buf[4096];
  const char* s = getenv("SRS_STORE");
  if (s && *s) snprintf(buf, sizeof buf, "%s", s);
  else { const char* h = getenv("HOME"); snprintf(buf, sizeof buf, "%s/.srs/store", h ? h : "."); }
  return (srs_str){(const uint8_t*)buf, (int64_t)strlen(buf)};
}
static void store_path(char* out, size_t n, srs_str dir, int64_t a, int64_t b, int64_t c, int64_t d) {
  snprintf(out, n, "%.*s/%lld.%lld.%lld.%lld", (int)dir.n, (const char*)dir.p, (long long)a, (long long)b, (long long)c, (long long)d);
}
static void mkdirs(const char* d) {
  char p[4096];
  snprintf(p, sizeof p, "%s", d);
  for (char* q = p + 1; *q; q++) if (*q == '/') { *q = 0; mkdir(p, 0755); *q = '/'; }
  mkdir(p, 0755);
}
// an entry is written to a temp file, then renamed: a reader sees a whole entry or none
typedef struct { FILE* f; char tmp[4200]; char dst[4200]; } store_out;
void* rt_out_new(srs_str dir, int64_t a, int64_t b, int64_t c, int64_t d) {
  store_out* o = malloc(sizeof *o);
  char dn[4096];
  if (!o || dir.n >= (int64_t)sizeof dn) { fputs("srs: store path too long\n", stderr); exit(70); }
  memcpy(dn, dir.p, (size_t)dir.n); dn[dir.n] = 0;
  mkdirs(dn);
  store_path(o->dst, sizeof o->dst, dir, a, b, c, d);
  snprintf(o->tmp, sizeof o->tmp, "%s.tmp%ld", o->dst, (long)getpid());
  o->f = fopen(o->tmp, "wb");
  if (!o->f) { fprintf(stderr, "srs: cannot write %s\n", o->tmp); exit(70); }
  return o;
}
int64_t rt_out_str(void* self, srs_str s) { fwrite(s.p, 1, (size_t)s.n, ((store_out*)self)->f); return 0; }
int64_t rt_out_i64(void* self, int64_t v) { fprintf(((store_out*)self)->f, "%lld", (long long)v); return 0; }
int64_t rt_out_commit(void* self) {
  store_out* o = self;
  if (fclose(o->f) != 0 || rename(o->tmp, o->dst) != 0) { fprintf(stderr, "srs: cannot commit %s\n", o->dst); exit(70); }
  free(o);
  return 0;
}
// the entry of a hash: its bytes, or length -1 when absent
srs_str rt_store_read(srs_str dir, int64_t a, int64_t b, int64_t c, int64_t d) {
  char name[4200];
  store_path(name, sizeof name, dir, a, b, c, d);
  return rt_read_file((srs_str){(const uint8_t*)name, (int64_t)strlen(name)});
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
// identity on a void* slot: the test of generic externs (vic-9l7.4 BD2, tests/s2/prog/generic.srs)
void* rt_same(void* x) { return x; }
// a non-null handle for tests of facts on types (vic-jxk, tests/s2/prog/type_facts.srs)
void* rt_handle(void) { static int64_t h; return &h; }
