#ifndef NXS_FLASH_STORAGE_H
#define NXS_FLASH_STORAGE_H

#include "nxs_flash_geometry.h"

/** Call on core 0 before launching core 1 or initializing USB. Does not erase/program flash or write status registers. */
bool nxs_flash_storage_init(void);
const nxs_flash_geometry_t *nxs_flash_storage_geometry(void);
const nxs_storage_io_t *nxs_flash_storage_io(void);
bool nxs_flash_storage_writable(void);

#endif
