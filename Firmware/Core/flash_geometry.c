#include "nxs_flash_geometry.h"

#include <string.h>

#define NXS_SFDP_HEADER_BYTES 8u
#define NXS_SFDP_PARAMETER_HEADER_BYTES 8u
#define NXS_SFDP_BASIC_DWORDS 9u
#define NXS_SFDP_DENSITY_OFFSET 4u
#define NXS_SFDP_ERASE_TYPES_OFFSET 28u
#define NXS_SFDP_ERASE_TYPE_COUNT 4u

static uint32_t read_u32(const uint8_t *bytes) {
    uint32_t value = 0;
    for (size_t index = 0; index < 4; ++index) {
        value |= (uint32_t)bytes[index] << (8u * index);
    }
    return value;
}

bool nxs_flash_geometry_decode(const uint8_t jedec[3], const uint8_t *sfdp, size_t length, uint32_t image_end,
                               nxs_flash_geometry_t *geometry) {
    static const uint8_t supported_jedec[] = {0x85, 0x20, 0x16};
    if (!jedec || !sfdp || !geometry || memcmp(jedec, supported_jedec, sizeof(supported_jedec)) != 0 || length < NXS_SFDP_HEADER_BYTES ||
        memcmp(sfdp, "SFDP", 4) != 0 || sfdp[4] != 0 || sfdp[5] != 1 || sfdp[7] != 0xff) {
        return false;
    }
    size_t parameter_count = (size_t)sfdp[6] + 1u;
    if (parameter_count > (length - NXS_SFDP_HEADER_BYTES) / NXS_SFDP_PARAMETER_HEADER_BYTES) {
        return false;
    }
    const uint8_t *basic = NULL;
    for (size_t index = 0; index < parameter_count; ++index) {
        const uint8_t *header = sfdp + NXS_SFDP_HEADER_BYTES + index * NXS_SFDP_PARAMETER_HEADER_BYTES;
        if (header[0] != 0 || header[7] != 0xff) {
            continue;
        }
        size_t pointer = (size_t)header[4] | ((size_t)header[5] << 8) | ((size_t)header[6] << 16);
        size_t bytes = (size_t)header[3] * 4u;
        if (basic || header[1] != 0 || header[2] != 1 || header[3] < NXS_SFDP_BASIC_DWORDS || pointer > length ||
            bytes > length - pointer) {
            return false;
        }
        basic = sfdp + pointer;
    }
    if (!basic || ((read_u32(basic) >> 17) & 3u) > 1u) {
        return false;
    }
    uint32_t density = read_u32(basic + NXS_SFDP_DENSITY_OFFSET);
    uint64_t bits;
    if (density & 0x80000000u) {
        uint32_t exponent = density & 0x7fffffffu;
        if (exponent >= 64) {
            return false;
        }
        bits = UINT64_C(1) << exponent;
    } else {
        bits = (uint64_t)density + 1u;
    }
    if (bits != (uint64_t)NXS_FLASH_SUPPORTED_BYTES * 8u || image_end == 0 ||
        image_end > NXS_FLASH_SUPPORTED_BYTES - NXS_FLASH_RESERVED_BYTES) {
        return false;
    }
    bool sector_supported = false;
    for (size_t index = 0; index < NXS_SFDP_ERASE_TYPE_COUNT; ++index) {
        const uint8_t *erase = basic + NXS_SFDP_ERASE_TYPES_OFFSET + index * 2u;
        if (erase[0] == 12 && erase[1] == 0x20) {
            sector_supported = true;
        }
    }
    if (!sector_supported) {
        return false;
    }
    nxs_flash_geometry_t candidate = {.flash_size_bytes = NXS_FLASH_SUPPORTED_BYTES};
    for (unsigned int index = 0; index < NXS_STORAGE_SLOT_COUNT; ++index) {
        candidate.slot_offsets[index] = NXS_FLASH_SUPPORTED_BYTES - NXS_FLASH_RESERVED_BYTES + index * NXS_STORAGE_SECTOR_BYTES;
    }
    *geometry = candidate;
    return true;
}
