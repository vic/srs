// the capability a C extern receives as its leading param, opaque: only the emitted program knows its layout
#include <stdint.h>
typedef struct srs_cap srs_cap;
void* srs_cap_alloc(srs_cap* c, int64_t size);
