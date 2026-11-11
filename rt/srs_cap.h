// the capability a C extern receives as its leading param, opaque: only the emitted program knows its layout
#include <stdint.h>
typedef struct srs_cap srs_cap;
void* srs_cap_alloc(srs_cap* c, int64_t size);
int64_t rt_out_flush(void);
// program-lifetime pages (srs_rt.c srs_pages), advised for transparent huge pages: snx word arrays; the Arena is srs now
void* srs_pages(int64_t size);
