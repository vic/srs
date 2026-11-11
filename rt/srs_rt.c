// srs runtime: C ABI services bound by `extern def` in lib/prelude.srs.
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <dirent.h>
#include <pthread.h>
#include <spawn.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>

typedef struct { const uint8_t* p; int64_t n; } srs_str;

static int g_argc;
static char** g_argv;

// ── output buffers (vic-xg9m R2a): rt_print and the store writers append to a growable byte buffer (doubled on growth);
// stdout's buffer is written by one write(1) loop at the flush points: process exit, before a spawn or fork (a child
// writes to the same stdout), rt_exit. A write error is exit 70 (_exit: this may run in atexit)
typedef struct { char* p; size_t n, cap; } obuf;
static void obuf_put(obuf* b, const void* s, size_t n) {
  if (b->n + n > b->cap) {
    size_t c = b->cap ? b->cap : 4096;
    while (c < b->n + n) c *= 2;
    char* q = realloc(b->p, c);
    if (!q) { fputs("srs: out of memory\n", stderr); _exit(70); }
    b->p = q; b->cap = c;
  }
  if (n) memcpy(b->p + b->n, s, n);
  b->n += n;
}
static bool wr_all(int fd, const char* p, size_t n) {
  while (n > 0) {
    ssize_t k = write(fd, p, n);
    if (k < 0) { if (errno == EINTR) continue; return false; }
    p += k; n -= (size_t)k;
  }
  return true;
}
static obuf g_stdout;
static bool g_atexit;
static void out_flush(void) {
  if (!wr_all(1, g_stdout.p, g_stdout.n)) { fputs("srs: cannot write stdout\n", stderr); _exit(70); }
  g_stdout.n = 0;
}

// ── main's stack (A14): $SRS_STACK bytes (suffix k, m or g), else srs_main_stack, which a program's own C may define
// (a weak 0 here: main runs on the process stack). Set: rt_init calls main again on a thread whose stack is that size,
// then exits with its result. No re-exec, no rlimit: perf and valgrind see one process
int64_t srs_main_stack __attribute__((weak)) = 0;
extern int main(int argc, char** argv) __attribute__((weak));
static bool g_on_stack;
static int64_t stack_want(void) {
  const char* s = getenv("SRS_STACK");
  if (!s || !*s) return srs_main_stack;
  char* e;
  long long v = strtoll(s, &e, 10);
  int64_t m = (*e == 'k' || *e == 'K') ? 1 << 10 : (*e == 'm' || *e == 'M') ? 1 << 20 : (*e == 'g' || *e == 'G') ? 1 << 30 : 1;
  if (m != 1) e++;
  if (v <= 0 || *e || v > ((int64_t)1 << 46) / m) { fprintf(stderr, "srs: SRS_STACK=%s ignored: want bytes, suffix k, m or g\n", s); return 0; }
  return (int64_t)v * m;
}
static void* main_on_stack(void* rc) { *(int*)rc = main(g_argc, g_argv); return 0; }
void rt_init(int argc, char** argv) {
  g_argc = argc; g_argv = argv;
  if (g_on_stack || !main) return;
  int64_t want = stack_want();
  if (want <= 0) return;
  size_t page = (size_t)sysconf(_SC_PAGESIZE), n = ((size_t)want + page - 1) / page * page;
  // reserved, not committed: pages fault in as the recursion reaches them; the lowest page is the guard
  char* base = mmap(0, n + page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_STACK, -1, 0);
  pthread_attr_t at;
  pthread_t t;
  int rc = 0;
  if (base == MAP_FAILED) { fprintf(stderr, "srs: no %lld-byte stack: main runs on the process stack\n", (long long)want); return; }
  g_on_stack = true;
  if (mprotect(base, page, PROT_NONE) != 0 || pthread_attr_init(&at) != 0 || pthread_attr_setstack(&at, base + page, n) != 0
      || pthread_create(&t, &at, main_on_stack, &rc) != 0) {
    g_on_stack = false;
    munmap(base, n + page);
    fprintf(stderr, "srs: no %lld-byte stack thread: main runs on the process stack\n", (long long)want);
    return;
  }
  pthread_join(t, 0);
  exit(rc);
}

int64_t rt_argc(void) { return g_argc; }
srs_str rt_arg(int64_t i) {
  if (i < 0 || i >= g_argc) return (srs_str){(const uint8_t*)"", 0};
  return (srs_str){(const uint8_t*)g_argv[i], (int64_t)strlen(g_argv[i])};
}

// Arena allocator: linked chunks, bump allocation, freed as a whole.
typedef struct chunk { struct chunk* next; size_t used, cap; } chunk;
typedef struct { chunk* head; } arena;
enum { CHUNK = 1 << 20 };
// freed CHUNK-size chunks (A14), taken before malloc: their pages are already faulted in. One list per process: the
// program runs one thread. Bigger chunks go back to malloc
static chunk* g_spare;
#ifdef SNX_CENSUS
// census: live malloc'd chunks (spare ones included, they stay allocated) and their bytes with header
static int64_t g_cz_chunks, g_cz_bytes;
int64_t srs_cz_chunks(void) { return g_cz_chunks; }
int64_t srs_cz_bytes(void) { return g_cz_bytes; }
// the arena that last took a chunk: its head chunk is the one still filling (only its used bytes count)
static arena* g_cz_last;
int64_t srs_cz_head_untouched(void) { return g_cz_last && g_cz_last->head ? (int64_t)(g_cz_last->head->cap - g_cz_last->head->used) : 0; }
// set by rt_arena_free just before it calls the snx side (weak: absent when snx_rt.c has no census)
static int64_t g_cz_s_region, g_cz_s_n;
int64_t srs_cz_s_region(void) { return g_cz_s_region; }
int64_t srs_cz_s_n(void) { return g_cz_s_n; }
__attribute__((weak)) void snx_cz_sample(void);
int64_t srs_cz_spare_n(void) { int64_t n = 0; for (chunk* c = g_spare; c; c = c->next) n++; return n; }
int64_t srs_cz_spare_bytes(void) { int64_t b = 0; for (chunk* c = g_spare; c; c = c->next) b += (int64_t)(sizeof(chunk) + c->cap); return b; }
#endif

void* rt_arena_new(void) { return calloc(1, sizeof(arena)); }
void* rt_arena_alloc(void* self, int64_t size) {
  arena* a = self;
  size_t n = ((size_t)size + 7) & ~(size_t)7;  // 8-byte granule, as the inline bump (s2/emit.srs Emit.allocFast)
  if (!a->head || a->head->used + n > a->head->cap) {
    size_t cap = n > CHUNK ? n : CHUNK;
    chunk* c = cap == CHUNK && g_spare ? g_spare : malloc(sizeof(chunk) + cap);
    if (!c) { fputs("srs: out of memory\n", stderr); exit(70); }
    if (c == g_spare) g_spare = c->next;
#ifdef SNX_CENSUS
    else { g_cz_chunks++; g_cz_bytes += (int64_t)(sizeof(chunk) + cap); }
    g_cz_last = a;
#endif
    c->next = a->head; c->used = 0; c->cap = cap; a->head = c;
  }
  void* p = (char*)(a->head + 1) + a->head->used;
  a->head->used += n;
  return p;
}
int64_t rt_arena_free(void* self) {
  arena* a = self;
#ifdef SNX_CENSUS
  if (g_cz_last == a) g_cz_last = 0;
  { // sample before the chunks move to g_spare: this arena's chunks (head counted by used bytes) and the spare list
    int64_t n = 0, reg = 0;
    for (chunk* c = a->head; c; c = c->next) { n++; reg += (int64_t)sizeof(chunk) + (c == a->head ? (int64_t)c->used : (int64_t)c->cap); }
    if (n > 100 && snx_cz_sample) { g_cz_s_region = reg; g_cz_s_n = n; snx_cz_sample(); }
  }
#endif
  for (chunk* c = a->head; c;) {
    chunk* n = c->next;
    if (c->cap == CHUNK) { c->next = g_spare; g_spare = c; } else {
#ifdef SNX_CENSUS
      g_cz_chunks--; g_cz_bytes -= (int64_t)(sizeof(chunk) + c->cap);
#endif
      free(c);
    }
    c = n;
  }
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

// ── the outside world (A13): bound only in the Srs.Files/Env/Clock/Net/Process handlers of lib/prelude.srs, which turn
// these results into Os.* values. A failure is an OS code: a Str of length -code, or the code as an I64 (0 = ok).
// The codes are Os.err's (lib/prelude.srs): 1 NotFound, 2 Denied, 3 NotDir, 4 IsDir, 5 Loop, 6 TooLong, 7 BadPath (a
// NUL byte in a path or name: refused, never cut short), 8 Refused, 9 Closed, OS_OTHER + errno for the rest
enum { OS_BADPATH = 7, OS_CLOSED = 9, OS_OTHER = 1000 };
static int64_t os_code(int e) {
  switch (e) {
    case ENOENT: return 1;
    case EACCES: case EPERM: return 2;
    case ENOTDIR: return 3;
    case EISDIR: return 4;
    case ELOOP: return 5;
    case ENAMETOOLONG: return 6;
    case ECONNREFUSED: return 8;
    case EPIPE: case ECONNRESET: case ENOTCONN: case EBADF: return OS_CLOSED;
    default: return OS_OTHER + e;
  }
}
static srs_str os_fail(int64_t code) { return (srs_str){(const uint8_t*)"", -code}; }
static uint8_t* os_bytes(size_t n) {
  uint8_t* p = malloc(n ? n : 1);
  if (!p) { fputs("srs: out of memory\n", stderr); exit(70); }
  return p;
}
// s as a C string (program-lifetime scratch), or 0 when s holds a NUL byte
static char* os_cstr(srs_str s) {
  if (s.n < 0 || memchr(s.p, 0, (size_t)s.n)) return 0;
  char* c = (char*)os_bytes((size_t)s.n + 1);
  memcpy(c, s.p, (size_t)s.n); c[s.n] = 0;
  return c;
}
static srs_str os_own(char* c) { return (srs_str){(const uint8_t*)c, (int64_t)strlen(c)}; }

// every byte up to the end of the file, also when st_size says 0 (/proc, pipes: snx Nx__readFile)
srs_str rt_fs_read_all(srs_str path) {
  char* c = os_cstr(path);
  if (!c) return os_fail(OS_BADPATH);
  FILE* f = fopen(c, "rb");
  free(c);
  if (!f) return os_fail(os_code(errno));
  size_t cap = 65536, o = 0, k;
  uint8_t* p = os_bytes(cap);
  while ((k = fread(p + o, 1, cap - o, f)) > 0) {
    o += k;
    if (o == cap) { p = realloc(p, cap *= 2); if (!p) { fputs("srs: out of memory\n", stderr); exit(70); } }
  }
  int bad = ferror(f);
  int e = errno;
  fclose(f);
  if (bad) { free(p); return os_fail(os_code(e)); }
  return (srs_str){p, (int64_t)o};
}
// the st_size bytes of a regular file (snx Nx__fileBytes); a directory is IsDir
srs_str rt_fs_bytes(srs_str path) {
  char* c = os_cstr(path);
  if (!c) return os_fail(OS_BADPATH);
  FILE* f = fopen(c, "rb");
  free(c);
  if (!f) return os_fail(os_code(errno));
  struct stat st;
  if (fstat(fileno(f), &st) != 0) { int e = errno; fclose(f); return os_fail(os_code(e)); }
  if (S_ISDIR(st.st_mode)) { fclose(f); return os_fail(os_code(EISDIR)); }
  size_t want = (size_t)st.st_size;
  uint8_t* b = os_bytes(want);
  size_t got = fread(b, 1, want, f);
  int bad = ferror(f);
  int e = errno;
  fclose(f);
  if (bad) { free(b); return os_fail(os_code(e)); }
  return (srs_str){b, (int64_t)got};
}
// the kind at path (Os.Kind order): 0 absent (stat failed), 1 regular, 2 directory, 3 symlink, 4 other; follow: stat,
// else lstat (snx Nx__fsKind)
int64_t rt_fs_kind(srs_str path, bool follow) {
  char* c = os_cstr(path);
  if (!c) return 0;
  struct stat st;
  int r = follow ? stat(c, &st) : lstat(c, &st);
  free(c);
  if (r != 0) return 0;
  return S_ISREG(st.st_mode) ? 1 : S_ISDIR(st.st_mode) ? 2 : S_ISLNK(st.st_mode) ? 3 : 4;
}
// a regular file its owner may execute, by lstat (snx Nx__fsExec)
bool rt_fs_exec(srs_str path) {
  char* c = os_cstr(path);
  if (!c) return false;
  struct stat st;
  int r = lstat(c, &st);
  free(c);
  return r == 0 && S_ISREG(st.st_mode) && (st.st_mode & S_IXUSR);
}
static int os_name_cmp(const void* a, const void* b) { return strcmp(*(char* const*)a, *(char* const*)b); }
// the entry names of a directory but . and .., sorted by bytes, each followed by a NUL (snx Nx__dirNames, sorted)
srs_str rt_fs_list(srs_str path) {
  char* c = os_cstr(path);
  if (!c) return os_fail(OS_BADPATH);
  DIR* d = opendir(c);
  free(c);
  if (!d) return os_fail(os_code(errno));
  size_t cap = 64, k = 0, bytes = 0;
  char** v = (char**)os_bytes(cap * sizeof(char*));
  struct dirent* e;
  errno = 0;
  while ((e = readdir(d))) {
    if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
    if (k == cap) { v = realloc(v, (cap *= 2) * sizeof(char*)); if (!v) { fputs("srs: out of memory\n", stderr); exit(70); } }
    size_t l = strlen(e->d_name) + 1;
    v[k] = (char*)os_bytes(l); memcpy(v[k], e->d_name, l); k++; bytes += l;
  }
  int err = errno;
  closedir(d);
  if (err) { for (size_t i = 0; i < k; i++) free(v[i]); free(v); return os_fail(os_code(err)); }
  qsort(v, k, sizeof(char*), os_name_cmp);
  uint8_t* o = os_bytes(bytes);
  size_t at = 0;
  for (size_t i = 0; i < k; i++) { size_t l = strlen(v[i]) + 1; memcpy(o + at, v[i], l); at += l; free(v[i]); }
  free(v);
  return (srs_str){o, (int64_t)bytes};
}
// the target of a symlink (snx Nx__readLink, any length)
srs_str rt_fs_readlink(srs_str path) {
  char* c = os_cstr(path);
  if (!c) return os_fail(OS_BADPATH);
  for (size_t cap = 256;; cap *= 2) {
    uint8_t* b = os_bytes(cap);
    ssize_t n = readlink(c, (char*)b, cap);
    if (n < 0) { int e = errno; free(b); free(c); return os_fail(os_code(e)); }
    if ((size_t)n < cap) { free(c); return (srs_str){b, (int64_t)n}; }
    free(b);
  }
}
// the path with every symlink, . and .. resolved (snx Nx__realPath, which keeps path on failure)
srs_str rt_fs_realpath(srs_str path) {
  char* c = os_cstr(path);
  if (!c) return os_fail(OS_BADPATH);
  char* r = realpath(c, NULL);
  int e = errno;
  free(c);
  return r ? os_own(r) : os_fail(os_code(e));
}
// the working directory (snx Nx__cwd, which says "/" on failure)
srs_str rt_fs_cwd(void) {
  for (size_t cap = 256;; cap *= 2) {
    char* b = (char*)os_bytes(cap);
    if (getcwd(b, cap)) return os_own(b);
    int e = errno;
    free(b);
    if (e != ERANGE) return os_fail(os_code(e));
  }
}
// the variable's value; length -1 when unset (snx Nx__getEnv says "" then: Os.Unset tells them apart)
srs_str rt_env_get(srs_str name) {
  char* c = os_cstr(name);
  if (!c) return os_fail(1);
  const char* v = getenv(c);
  free(c);
  return v ? (srs_str){(const uint8_t*)v, (int64_t)strlen(v)} : os_fail(1);
}
// seconds since the epoch (snx Nx__timeNow)
int64_t rt_clock_now(void) { return (int64_t)time(0); }

// a client stream to a Unix socket (snx rt/snx_net.c): the state of a Srs.Net handle; fd -1 = no connection (its ops fail with EBADF = Os.Closed)
typedef struct { int fd; } os_net;
void* rt_net_new(void) {
  os_net* s = (os_net*)os_bytes(sizeof *s);
  s->fd = -1;
  return s;
}
int64_t rt_net_connect(void* self, srs_str path) {
  os_net* s = self;
  struct sockaddr_un a = {.sun_family = AF_UNIX};
  if (path.n <= 0 || memchr(path.p, 0, (size_t)path.n)) return OS_BADPATH;
  if ((size_t)path.n >= sizeof a.sun_path) return os_code(ENAMETOOLONG);
  memcpy(a.sun_path, path.p, (size_t)path.n);
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) return os_code(errno);
  if (connect(fd, (struct sockaddr*)&a, sizeof a) != 0) { int e = errno; close(fd); return os_code(e); }
  s->fd = fd;
  return 0;
}
// all of b written (MSG_NOSIGNAL: a gone peer is Closed, not SIGPIPE)
int64_t rt_net_send(void* self, srs_str b) {
  os_net* s = self;
  for (int64_t o = 0; o < b.n;) {
    ssize_t k = send(s->fd, b.p + o, (size_t)(b.n - o), MSG_NOSIGNAL);
    if (k < 0 && errno == EINTR) continue;
    if (k <= 0) return k < 0 ? os_code(errno) : OS_CLOSED;
    o += k;
  }
  return 0;
}
// up to n bytes, fewer only at the end of the stream (snx Nx__netRead)
srs_str rt_net_recv(void* self, int64_t n) {
  os_net* s = self;
  if (n < 0) n = 0;
  uint8_t* p = os_bytes((size_t)n);
  int64_t o = 0;
  while (o < n) {
    ssize_t k = read(s->fd, p + o, (size_t)(n - o));
    if (k < 0 && errno == EINTR) continue;
    if (k < 0) { int e = errno; free(p); return os_fail(os_code(e)); }
    if (k == 0) break;
    o += k;
  }
  return (srs_str){p, o};
}
// every byte up to the end of the stream (snx Nx__netDrain)
srs_str rt_net_drain(void* self) {
  os_net* s = self;
  size_t cap = 65536, o = 0;
  uint8_t* p = os_bytes(cap);
  for (;;) {
    if (o == cap) { p = realloc(p, cap *= 2); if (!p) { fputs("srs: out of memory\n", stderr); exit(70); } }
    ssize_t k = read(s->fd, p + o, cap - o);
    if (k < 0 && errno == EINTR) continue;
    if (k < 0) { int e = errno; free(p); return os_fail(os_code(e)); }
    if (k == 0) return (srs_str){p, (int64_t)o};
    o += (size_t)k;
  }
}
int64_t rt_net_close(void* self) {
  os_net* s = self;
  if (s->fd >= 0) close(s->fd);
  s->fd = -1;
  return 0;
}

// a child process: argv built by rt_proc_arg, run once by rt_proc_run (PATH search as execvp), waited for. The result
// is how * OS_HOW + val. how: 0 exited (val = exit code), 1 killed (val = signal), 2 not started (val = OS code)
enum { OS_HOW = 1 << 20 };
typedef struct { char** argv; size_t n, cap; bool bad; } os_proc;
void* rt_proc_new(void) {
  os_proc* p = (os_proc*)os_bytes(sizeof *p);
  p->cap = 8; p->n = 0; p->bad = false;
  p->argv = (char**)os_bytes(p->cap * sizeof(char*));
  p->argv[0] = 0;
  return p;
}
int64_t rt_proc_arg(void* self, srs_str a) {
  os_proc* p = self;
  char* c = os_cstr(a);
  if (!c) { p->bad = true; return 0; }
  if (p->n + 1 == p->cap) { p->argv = realloc(p->argv, (p->cap *= 2) * sizeof(char*)); if (!p->argv) { fputs("srs: out of memory\n", stderr); exit(70); } }
  p->argv[p->n++] = c; p->argv[p->n] = 0;
  return 0;
}
extern char** environ;
int64_t rt_proc_run(void* self) {
  os_proc* p = self;
  pid_t pid;
  int st;
  out_flush();
  int64_t r;
  if (p->bad || p->n == 0) r = 2 * OS_HOW + OS_BADPATH;
  else {
    int e = posix_spawnp(&pid, p->argv[0], 0, 0, p->argv, environ);
    if (e != 0) r = 2 * OS_HOW + os_code(e);
    else {
      int w;
      while ((w = waitpid(pid, &st, 0)) < 0 && errno == EINTR) {}
      r = w < 0 ? 2 * OS_HOW + os_code(errno) : WIFSIGNALED(st) ? OS_HOW + WTERMSIG(st) : WEXITSTATUS(st);
    }
  }
  for (size_t i = 0; i < p->n; i++) free(p->argv[i]);
  free(p->argv);
  free(p);
  return r;
}

// a test server (tests/s2/prog/os_net.srs): a Unix socket that a child process serves once: it reads 4 bytes, writes
// them back twice, then closes. Returns the socket path
srs_str ext_net_echo(void) {
  static char path[64];
  snprintf(path, sizeof path, "/tmp/srs-net-%ld.sock", (long)getpid());
  unlink(path);
  struct sockaddr_un a = {.sun_family = AF_UNIX};
  memcpy(a.sun_path, path, strlen(path));
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0 || bind(fd, (struct sockaddr*)&a, sizeof a) != 0 || listen(fd, 1) != 0) return os_own(path);
  out_flush();
  if (fork() == 0) {
    alarm(2);
    int c = accept(fd, 0, 0);
    char b[4];
    size_t got = 0;
    while (c >= 0 && got < 4) { ssize_t k = read(c, b + got, 4 - got); if (k <= 0) break; got += (size_t)k; }
    if (c >= 0) { (void)!write(c, b, got); (void)!write(c, b, got); close(c); }
    unlink(path);
    _exit(0);
  }
  close(fd);
  return os_own(path);
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
typedef struct { int fd; obuf b; char tmp[4200]; char dst[4200]; } store_out;
void* rt_out_new(srs_str dir, int64_t a, int64_t b, int64_t c, int64_t d) {
  store_out* o = malloc(sizeof *o);
  char dn[4096];
  if (!o || dir.n >= (int64_t)sizeof dn) { fputs("srs: store path too long\n", stderr); exit(70); }
  memcpy(dn, dir.p, (size_t)dir.n); dn[dir.n] = 0;
  mkdirs(dn);
  store_path(o->dst, sizeof o->dst, dir, a, b, c, d);
  snprintf(o->tmp, sizeof o->tmp, "%s.tmp%ld", o->dst, (long)getpid());
  o->fd = open(o->tmp, O_WRONLY | O_CREAT | O_TRUNC, 0666);
  if (o->fd < 0) { fprintf(stderr, "srs: cannot write %s\n", o->tmp); exit(70); }
  o->b = (obuf){0, 0, 0};
  return o;
}
int64_t rt_out_str(void* self, srs_str s) { obuf_put(&((store_out*)self)->b, s.p, (size_t)s.n); return 0; }
int64_t rt_out_i64(void* self, int64_t v) { char t[24]; int k = snprintf(t, sizeof t, "%lld", (long long)v); obuf_put(&((store_out*)self)->b, t, (size_t)k); return 0; }
int64_t rt_out_commit(void* self) {
  store_out* o = self;
  bool ok = wr_all(o->fd, o->b.p, o->b.n);
  free(o->b.p);
  if (close(o->fd) != 0 || !ok || rename(o->tmp, o->dst) != 0) { fprintf(stderr, "srs: cannot commit %s\n", o->dst); exit(70); }
  free(o);
  return 0;
}
// the entry of a hash: its bytes, or length -1 when absent
srs_str rt_store_read(srs_str dir, int64_t a, int64_t b, int64_t c, int64_t d) {
  char name[4200];
  store_path(name, sizeof name, dir, a, b, c, d);
  return rt_read_file((srs_str){(const uint8_t*)name, (int64_t)strlen(name)});
}

// where rt_print writes: stdout, or the capture buffer between rt_capture_begin and rt_capture_end (a printer's output
// as one string; the bytes live until the program ends)
static obuf g_cap;
static bool g_capturing;
// stdout's buffer is bounded at 1 MiB: an append that would pass it writes the buffer out first (one bigger than the
// bound is written directly); a capture is not bounded, its text is returned to the program
#define OUT_MAX ((size_t)1 << 20)
static __attribute__((noinline)) void out_slow(const void* s, size_t n) {
  if (g_capturing) { obuf_put(&g_cap, s, n); return; }
  if (!g_atexit) { g_atexit = true; atexit(out_flush); }
  if (g_stdout.n + n > OUT_MAX) {
    out_flush();
    if (n > OUT_MAX) { if (!wr_all(1, s, n)) { fputs("srs: cannot write stdout\n", stderr); _exit(70); } return; }
  }
  obuf_put(&g_stdout, s, n);
}
// the hot path: stdout open, the bytes fit the buffer's capacity with a spare byte (a power of two <= OUT_MAX, grown only by out_slow)
static inline void out_put(const void* s, size_t n) {
  if (!g_capturing && g_atexit && g_stdout.n + n < g_stdout.cap) { memcpy(g_stdout.p + g_stdout.n, s, n); g_stdout.n += n; return; }
  out_slow(s, n);
}
int64_t rt_capture_begin(void) {
  g_cap = (obuf){0, 0, 0}; // a fresh buffer: the previous capture's bytes live on
  obuf_put(&g_cap, "", 0);
  g_capturing = true;
  return 0;
}
srs_str rt_capture_end(void) {
  if (!g_capturing) { fputs("srs: capture not open\n", stderr); exit(70); }
  g_capturing = false;
  return (srs_str){(const uint8_t*)(g_cap.p ? g_cap.p : ""), (int64_t)g_cap.n};
}
int64_t rt_print(srs_str s) { out_put(s.p, (size_t)s.n); return 0; }
int64_t rt_eprint(srs_str s) { fwrite(s.p, 1, (size_t)s.n, stderr); return 0; }
int64_t rt_print_i64(int64_t v) { char t[24]; int k = snprintf(t, sizeof t, "%lld", (long long)v); out_put(t, (size_t)k); return 0; }
int64_t rt_eprint_i64(int64_t v) { fprintf(stderr, "%lld", (long long)v); return 0; }
int64_t rt_print_char(int64_t c) { char t = (char)(unsigned char)c; out_put(&t, 1); return 0; }
int64_t rt_str_len(srs_str s) { return s.n; }
int64_t rt_str_at(srs_str s, int64_t i) { return (i >= 0 && i < s.n) ? s.p[i] : -1; }
srs_str rt_str_slice(srs_str s, int64_t b, int64_t e) {
  if (b < 0) b = 0;
  if (e > s.n) e = s.n;
  if (e < b) e = b;
  return (srs_str){s.p + b, e - b};
}
bool rt_str_eq(srs_str a, srs_str b) { return a.n == b.n && memcmp(a.p, b.p, (size_t)a.n) == 0; }
int64_t rt_exit(int64_t code) { out_flush(); exit((int)code); }
// identity on a void* slot: the test of generic externs (vic-9l7.4 BD2, tests/s2/prog/generic.srs)
void* ext_same(void* x) { return x; }
// a non-null handle for tests of facts on types (vic-jxk, tests/s2/prog/type_facts.srs)
void* ext_handle(void) { static int64_t h; return &h; }
// Srs.noState: the state of a handler that keeps none (s2/parse.srs Parse.stateless)
void* Srs__noState(void) { return 0; }
// the pure string primitives Str.len, Str.at, Str.slice, Str.eq (lib/prelude.srs) are static inline in the emitted C
// (s2/emit.srs Emit.strPrims), with the semantics of rt_str_* above
