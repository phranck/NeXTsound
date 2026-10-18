#include "Fixtures/py25q32hb_sfdp.h"
#include "nxs_flash_geometry.h"
#include "nxs_test.h"

#include <string.h>

#define TEST_BASIC_OFFSET 48u
#define TEST_BASIC_END (TEST_BASIC_OFFSET + 36u)
#define TEST_IMAGE_END 0x10000u

static const uint8_t jedec[] = {0x85, 0x20, 0x16};

static void write_u32(uint8_t *bytes, uint32_t value) {
    for (size_t index = 0; index < 4; ++index) {
        bytes[index] = (uint8_t)(value >> (index * 8u));
    }
}

static void reject(const uint8_t *identity, const uint8_t *sfdp, size_t length, uint32_t image_end) {
    nxs_flash_geometry_t geometry;
    memset(&geometry, 0xa5, sizeof(geometry));
    uint8_t unchanged[sizeof(geometry)];
    memcpy(unchanged, &geometry, sizeof(geometry));
    CHECK(!nxs_flash_geometry_decode(identity, sfdp, length, image_end, &geometry));
    CHECK(memcmp(&geometry, unchanged, sizeof(geometry)) == 0);
}

static void recorded_geometry(void) {
    nxs_flash_geometry_t geometry;
    CHECK(nxs_flash_geometry_decode(jedec, py25q32hb_sfdp, sizeof(py25q32hb_sfdp), TEST_IMAGE_END, &geometry));
    CHECK(geometry.flash_size_bytes == 4194304u);
    CHECK(geometry.slot_offsets[0] == 0x3fe000u);
    CHECK(geometry.slot_offsets[1] == 0x3ff000u);
    CHECK(nxs_flash_geometry_decode(jedec, py25q32hb_sfdp, TEST_BASIC_END, TEST_IMAGE_END, &geometry));
    CHECK(nxs_flash_geometry_decode(jedec, py25q32hb_sfdp, sizeof(py25q32hb_sfdp), geometry.slot_offsets[0], &geometry));
    reject(jedec, py25q32hb_sfdp, sizeof(py25q32hb_sfdp), geometry.slot_offsets[0] + 1u);
    reject(jedec, py25q32hb_sfdp, sizeof(py25q32hb_sfdp), UINT32_MAX);
    reject(jedec, py25q32hb_sfdp, sizeof(py25q32hb_sfdp), 0);
    for (size_t length = 0; length < TEST_BASIC_END; ++length) {
        reject(jedec, py25q32hb_sfdp, length, TEST_IMAGE_END);
    }
    reject(NULL, py25q32hb_sfdp, sizeof(py25q32hb_sfdp), TEST_IMAGE_END);
    reject(jedec, NULL, sizeof(py25q32hb_sfdp), TEST_IMAGE_END);
    CHECK(!nxs_flash_geometry_decode(jedec, py25q32hb_sfdp, sizeof(py25q32hb_sfdp), TEST_IMAGE_END, NULL));
    for (size_t index = 0; index < sizeof(jedec); ++index) {
        uint8_t wrong[sizeof(jedec)];
        memcpy(wrong, jedec, sizeof(wrong));
        wrong[index] ^= 1u;
        reject(wrong, py25q32hb_sfdp, sizeof(py25q32hb_sfdp), TEST_IMAGE_END);
    }
}

static void malformed_metadata(void) {
    static const size_t offsets[] = {0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 15};
    for (size_t index = 0; index < sizeof(offsets) / sizeof(offsets[0]); ++index) {
        uint8_t corrupt[sizeof(py25q32hb_sfdp)];
        memcpy(corrupt, py25q32hb_sfdp, sizeof(corrupt));
        corrupt[offsets[index]] ^= 1u;
        reject(jedec, corrupt, sizeof(corrupt), TEST_IMAGE_END);
    }
    for (unsigned int kind = 0; kind < 9; ++kind) {
        uint8_t corrupt[sizeof(py25q32hb_sfdp)];
        memcpy(corrupt, py25q32hb_sfdp, sizeof(corrupt));
        switch (kind) {
        case 0:
            corrupt[6] = 0xff;
            break;
        case 1:
            corrupt[11] = 8;
            break;
        case 2:
            corrupt[12] = 250;
            break;
        case 3:
            corrupt[14] = 0xff;
            break;
        case 4:
            write_u32(corrupt + TEST_BASIC_OFFSET + 4, 0x7fffffffu);
            break;
        case 5:
            write_u32(corrupt + TEST_BASIC_OFFSET + 4, 0x80000040u);
            break;
        case 6:
            corrupt[TEST_BASIC_OFFSET + 29] = 0x21;
            break;
        case 7:
            corrupt[TEST_BASIC_OFFSET + 28] = 13;
            break;
        case 8:
            corrupt[6] = 2;
            memcpy(corrupt + 24, corrupt + 8, 8);
            break;
        }
        reject(jedec, corrupt, sizeof(corrupt), TEST_IMAGE_END);
    }
    for (unsigned int address_mode = 0; address_mode < 4; ++address_mode) {
        uint8_t candidate[sizeof(py25q32hb_sfdp)];
        memcpy(candidate, py25q32hb_sfdp, sizeof(candidate));
        candidate[TEST_BASIC_OFFSET + 2] = (uint8_t)((candidate[TEST_BASIC_OFFSET + 2] & ~6u) | (address_mode << 1));
        nxs_flash_geometry_t geometry;
        CHECK(nxs_flash_geometry_decode(jedec, candidate, sizeof(candidate), TEST_IMAGE_END, &geometry) == (address_mode < 2));
    }
    uint8_t exponential[sizeof(py25q32hb_sfdp)];
    memcpy(exponential, py25q32hb_sfdp, sizeof(exponential));
    write_u32(exponential + TEST_BASIC_OFFSET + 4, 0x80000019u);
    nxs_flash_geometry_t geometry;
    CHECK(nxs_flash_geometry_decode(jedec, exponential, sizeof(exponential), TEST_IMAGE_END, &geometry));
    CHECK(geometry.flash_size_bytes == NXS_FLASH_SUPPORTED_BYTES);
}

static void mutation_bounds(void) {
    for (size_t index = 0; index < sizeof(py25q32hb_sfdp); ++index) {
        uint8_t candidate[sizeof(py25q32hb_sfdp)];
        memcpy(candidate, py25q32hb_sfdp, sizeof(candidate));
        candidate[index] ^= 0xff;
        nxs_flash_geometry_t geometry;
        memset(&geometry, 0xa5, sizeof(geometry));
        uint8_t unchanged[sizeof(geometry)];
        memcpy(unchanged, &geometry, sizeof(geometry));
        if (nxs_flash_geometry_decode(jedec, candidate, sizeof(candidate), TEST_IMAGE_END, &geometry)) {
            CHECK(geometry.flash_size_bytes == NXS_FLASH_SUPPORTED_BYTES);
            CHECK(geometry.slot_offsets[0] == 0x3fe000u && geometry.slot_offsets[1] == 0x3ff000u);
        } else {
            CHECK(memcmp(&geometry, unchanged, sizeof(geometry)) == 0);
        }
    }
}

int main(void) {
    recorded_geometry();
    malformed_metadata();
    mutation_bounds();
    return nxs_test_finish("Flash geometry");
}
