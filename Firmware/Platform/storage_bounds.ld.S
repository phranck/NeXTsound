#include "nxs_storage_layout.h"

__nxs_storage_start = __flash_binary_start + NXS_FLASH_SUPPORTED_BYTES - NXS_FLASH_RESERVED_BYTES;
ASSERT(__flash_binary_end <= __nxs_storage_start, "NeXTsound firmware overlaps persistent snapshot sectors")
