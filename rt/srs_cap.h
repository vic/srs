// the capability a C extern receives as its leading param, opaque: only the emitted program knows its layout
#include <stdint.h>
typedef struct srs_cap srs_cap;
void* srs_cap_alloc(srs_cap* c, int64_t size);
int64_t rt_out_flush(void);
// arena chunk pages (srs_rt.c srs_pages): program-lifetime pages, advised for transparent huge pages
void* srs_pages(int64_t size);
