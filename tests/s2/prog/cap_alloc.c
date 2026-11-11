// the C extern of tests/s2/prog/cap_alloc.srs: its Str is allocated in the capability's Region through srs_cap_alloc
#include <stdint.h>
#include <string.h>
#include "../../../rt/srs_cap.h"
typedef struct { const uint8_t* p; int64_t n; } srs_str;
srs_str cap_text(srs_cap* r, int64_t n) {
  uint8_t* p = srs_cap_alloc(r, n);
  memset(p, 'x', (size_t)n);
  return (srs_str){p, n};
}
