#ifndef NXS_FLASH_GEOMETRY_H
#define NXS_FLASH_GEOMETRY_H

#include "nxs_storage.h"

#define NXS_FLASH_SFDP_BYTES 256u

typedef struct {
    uint32_t flash_size_bytes;
    uint32_t slot_offsets[NXS_STORAGE_SLOT_COUNT];
} nxs_flash_geometry_t;

/** Supports the observed PY25Q32HB JEDEC/SFDP 1.0 geometry. Image end is exclusive and relative to flash base. */
/** Failure leaves geometry unchanged. Unknown parts, metadata, or image overlap cannot enable storage writes. */
bool nxs_flash_geometry_decode(const uint8_t jedec[3], const uint8_t *sfdp, size_t length, uint32_t image_end,
                               nxs_flash_geometry_t *geometry);

#endif
