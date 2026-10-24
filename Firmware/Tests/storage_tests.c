#include "nxs_storage.h"
#include "nxs_test.h"

#include <limits.h>
#include <math.h>
#include <string.h>
#include <zlib.h>

#define TEST_CHECKSUM_OFFSET (NXS_STORAGE_PAGE_BYTES - 4u)
#define TEST_PAYLOAD_OFFSET 16u

typedef struct {
    uint8_t sectors[NXS_STORAGE_SLOT_COUNT][NXS_STORAGE_SECTOR_BYTES];
    size_t program_budget;
    size_t erase_budget;
    unsigned int calls;
    unsigned int fail_call;
    unsigned int erases;
    unsigned int programs;
    unsigned int last_erased;
    bool silent_erase_failure;
    bool corrupt_data;
    bool corrupt_commit;
} fake_flash_t;

static void write_u32(uint8_t *bytes, uint32_t value) {
    for (size_t index = 0; index < 4; ++index) {
        bytes[index] = (uint8_t)(value >> (8u * index));
    }
}

static uint32_t read_u32(const uint8_t *bytes) {
    uint32_t value = 0;
    for (size_t index = 0; index < 4; ++index) {
        value |= (uint32_t)bytes[index] << (8u * index);
    }
    return value;
}

static void refresh_checksum(nxs_storage_record_t *record) {
    uint32_t digest = (uint32_t)crc32(0, record->bytes, TEST_CHECKSUM_OFFSET);
    write_u32(record->bytes + TEST_CHECKSUM_OFFSET, digest);
    write_u32(record->bytes + NXS_STORAGE_PAGE_BYTES + 4, read_u32(record->bytes + 8));
    write_u32(record->bytes + NXS_STORAGE_PAGE_BYTES + 8, digest);
    write_u32(record->bytes + NXS_STORAGE_PAGE_BYTES + 12, ~digest);
}

static nxs_stored_state_t make_state(uint32_t generation, float attenuation) {
    nxs_stored_state_t state = {.snapshot = nxs_default_snapshot(), .generation = generation};
    state.snapshot.profile_id[0] = (uint8_t)generation;
    state.snapshot.profile_revision = generation;
    state.snapshot.attenuation_db = attenuation;
    return state;
}

static void check_state(const nxs_stored_state_t *actual, const nxs_stored_state_t *expected) {
    uint8_t actual_payload[NXS_SNAPSHOT_SIZE], expected_payload[NXS_SNAPSHOT_SIZE];
    CHECK(actual->generation == expected->generation);
    CHECK(nxs_snapshot_encode(&actual->snapshot, actual_payload, sizeof(actual_payload)) == NXS_RESULT_OK);
    CHECK(nxs_snapshot_encode(&expected->snapshot, expected_payload, sizeof(expected_payload)) == NXS_RESULT_OK);
    CHECK(memcmp(actual_payload, expected_payload, sizeof(actual_payload)) == 0);
    CHECK(strcmp(actual->device_name, expected->device_name) == 0);
}

static void fake_init(fake_flash_t *flash) {
    memset(flash, 0, sizeof(*flash));
    memset(flash->sectors, 0xff, sizeof(flash->sectors));
    flash->program_budget = SIZE_MAX;
    flash->erase_budget = SIZE_MAX;
    flash->last_erased = UINT_MAX;
}

static void seed(fake_flash_t *flash, unsigned int slot, const nxs_stored_state_t *state) {
    nxs_storage_record_t record;
    CHECK(slot < NXS_STORAGE_SLOT_COUNT);
    CHECK(nxs_storage_record_encode(state, &record));
    memcpy(flash->sectors[slot], record.bytes, sizeof(record.bytes));
}

static bool fake_read(void *context, unsigned int slot, nxs_storage_record_t *record) {
    fake_flash_t *flash = context;
    CHECK(slot < NXS_STORAGE_SLOT_COUNT);
    if (++flash->calls == flash->fail_call) {
        memset(record, 0xa5, sizeof(*record));
        return false;
    }
    memcpy(record->bytes, flash->sectors[slot], sizeof(record->bytes));
    return true;
}

static bool fake_erase(void *context, unsigned int slot) {
    fake_flash_t *flash = context;
    CHECK(slot < NXS_STORAGE_SLOT_COUNT);
    ++flash->erases;
    flash->last_erased = slot;
    if (++flash->calls == flash->fail_call) {
        return false;
    }
    size_t count = flash->erase_budget < NXS_STORAGE_SECTOR_BYTES ? flash->erase_budget : NXS_STORAGE_SECTOR_BYTES;
    if (!flash->silent_erase_failure) {
        memset(flash->sectors[slot], 0xff, count);
    }
    return count == NXS_STORAGE_SECTOR_BYTES;
}

static bool fake_program(void *context, unsigned int slot, unsigned int page, const uint8_t bytes[NXS_STORAGE_PAGE_BYTES]) {
    fake_flash_t *flash = context;
    CHECK(slot < NXS_STORAGE_SLOT_COUNT);
    CHECK(page == NXS_STORAGE_DATA_PAGE || page == NXS_STORAGE_COMMIT_PAGE);
    ++flash->programs;
    if (++flash->calls == flash->fail_call) {
        return false;
    }
    size_t count = flash->program_budget < NXS_STORAGE_PAGE_BYTES ? flash->program_budget : NXS_STORAGE_PAGE_BYTES;
    uint8_t *destination = flash->sectors[slot] + page * NXS_STORAGE_PAGE_BYTES;
    for (size_t index = 0; index < count; ++index) {
        destination[index] &= bytes[index];
    }
    if (flash->program_budget != SIZE_MAX) {
        flash->program_budget -= count;
    }
    if ((page == NXS_STORAGE_DATA_PAGE && flash->corrupt_data) || (page == NXS_STORAGE_COMMIT_PAGE && flash->corrupt_commit)) {
        destination[0] &= (uint8_t)~0x02u;
    }
    return count == NXS_STORAGE_PAGE_BYTES;
}

static nxs_storage_io_t fake_io(fake_flash_t *flash) {
    return (nxs_storage_io_t){.context = flash, .read = fake_read, .erase = fake_erase, .program = fake_program};
}

static void record_validation(void) {
    nxs_stored_state_t original = make_state(0x12345678u, -18.0f), decoded;
    nxs_storage_record_t record;
    CHECK(nxs_storage_record_encode(&original, &record));
    CHECK(memcmp(record.bytes, "NXSP", 4) == 0);
    CHECK(record.bytes[12] == 1 && record.bytes[13] == 0);
    CHECK(record.bytes[8] == 0x78 && record.bytes[9] == 0x56 && record.bytes[10] == 0x34 && record.bytes[11] == 0x12);
    CHECK(read_u32(record.bytes + TEST_CHECKSUM_OFFSET) == (uint32_t)crc32(0, record.bytes, TEST_CHECKSUM_OFFSET));
    CHECK(nxs_storage_record_decode(&record, &decoded));
    check_state(&decoded, &original);
    for (size_t byte_index = 0; byte_index < NXS_STORAGE_RECORD_BYTES; ++byte_index) {
        for (unsigned int bit = 0; bit < 8; ++bit) {
            nxs_storage_record_t corrupt = record;
            corrupt.bytes[byte_index] ^= (uint8_t)(1u << bit);
            memset(&decoded, 0xa5, sizeof(decoded));
            uint8_t unchanged[sizeof(decoded)];
            memcpy(unchanged, &decoded, sizeof(decoded));
            CHECK(!nxs_storage_record_decode(&corrupt, &decoded));
            CHECK(memcmp(&decoded, unchanged, sizeof(decoded)) == 0);
        }
    }
    for (unsigned int malformed = 0; malformed < 12; ++malformed) {
        nxs_storage_record_t corrupt = record;
        switch (malformed) {
        case 0:
            corrupt.bytes[4] = NXS_STORAGE_VERSION + 1u;
            break;
        case 1:
            corrupt.bytes[6] ^= 1u;
            break;
        case 2:
            write_u32(corrupt.bytes + 8, 0);
            break;
        case 3:
            corrupt.bytes[12] = NXS_SNAPSHOT_PROTOCOL_MAJOR + 1u;
            break;
        case 4:
            corrupt.bytes[13] = NXS_SNAPSHOT_PROTOCOL_MINOR + 1u;
            break;
        case 5:
            corrupt.bytes[14] = NXS_SNAPSHOT_SIZE - 1u;
            break;
        case 6:
            corrupt.bytes[TEST_PAYLOAD_OFFSET + NXS_SNAPSHOT_SIZE] = 0x01;
            break;
        case 7:
            corrupt.bytes[TEST_PAYLOAD_OFFSET + 22] = 1;
            break;
        case 8:
            corrupt.bytes[TEST_PAYLOAD_OFFSET + 21] = 2;
            break;
        case 9:
            write_u32(corrupt.bytes + TEST_PAYLOAD_OFFSET + 24, 0x7fc00000u);
            break;
        case 10:
            corrupt.bytes[NXS_STORAGE_PAGE_BYTES + 16] = 0;
            break;
        case 11:
            corrupt.bytes[TEST_PAYLOAD_OFFSET + NXS_SNAPSHOT_SIZE + NXS_DEVICE_NAME_LENGTH] = 0;
            break;
        }
        refresh_checksum(&corrupt);
        CHECK(!nxs_storage_record_decode(&corrupt, &decoded));
    }
    nxs_storage_record_t destination = record;
    original.generation = 0;
    CHECK(!nxs_storage_record_encode(&original, &destination));
    CHECK(memcmp(&destination, &record, sizeof(record)) == 0);
    original.generation = 1;
    original.snapshot.high_pass_hz = NAN;
    CHECK(!nxs_storage_record_encode(&original, &destination));
    CHECK(memcmp(&destination, &record, sizeof(record)) == 0);
    CHECK(!nxs_storage_record_encode(NULL, &destination));
    CHECK(!nxs_storage_record_encode(&original, NULL));
    CHECK(!nxs_storage_record_decode(NULL, &decoded));
    CHECK(!nxs_storage_record_decode(&record, NULL));
}

static void selection_and_generation(void) {
    fake_flash_t flash;
    fake_init(&flash);
    nxs_storage_io_t io = fake_io(&flash);
    nxs_stored_state_t first = make_state(7, -24.0f), second = make_state(8, -18.0f), loaded = make_state(99, -12.0f);
    unsigned int slot = UINT_MAX;
    CHECK(nxs_storage_read(&io, &loaded, &slot) == NXS_STORAGE_EMPTY);
    CHECK(loaded.generation == 99 && slot == UINT_MAX);
    CHECK(nxs_storage_save(&io, &first) == NXS_RESULT_OK);
    CHECK(flash.last_erased == 0 && flash.erases == 1 && flash.programs == 2);
    uint8_t previous_sector[NXS_STORAGE_SECTOR_BYTES];
    memcpy(previous_sector, flash.sectors[0], sizeof(previous_sector));
    CHECK(nxs_storage_save(&io, &second) == NXS_RESULT_OK);
    CHECK(flash.last_erased == 1 && flash.erases == 2 && flash.programs == 4);
    CHECK(memcmp(previous_sector, flash.sectors[0], sizeof(previous_sector)) == 0);
    CHECK(nxs_storage_read(&io, &loaded, &slot) == NXS_STORAGE_LOADED && slot == 1);
    check_state(&loaded, &second);
    CHECK(nxs_storage_save(&io, &second) == NXS_RESULT_OK);
    CHECK(nxs_storage_save(&io, &first) == NXS_RESULT_STALE_GENERATION);
    second.snapshot.attenuation_db = -30.0f;
    CHECK(nxs_storage_save(&io, &second) == NXS_RESULT_STALE_GENERATION);
    CHECK(flash.erases == 2 && flash.programs == 4);
    nxs_stored_state_t maximum = make_state(UINT32_MAX, -18.0f);
    CHECK(nxs_storage_save(&io, &maximum) == NXS_RESULT_OK);
    CHECK(nxs_storage_save(&io, &first) == NXS_RESULT_STALE_GENERATION);
    CHECK(nxs_storage_read(&io, &loaded, &slot) == NXS_STORAGE_LOADED);
    check_state(&loaded, &maximum);

    fake_init(&flash);
    seed(&flash, 0, &first);
    seed(&flash, 1, &first);
    CHECK(nxs_storage_read(&io, &loaded, &slot) == NXS_STORAGE_LOADED && slot == 0);
    nxs_stored_state_t conflict = first;
    conflict.snapshot.attenuation_db = -20.0f;
    seed(&flash, 1, &conflict);
    loaded.generation = 99;
    slot = UINT_MAX;
    CHECK(nxs_storage_read(&io, &loaded, &slot) == NXS_STORAGE_AMBIGUOUS);
    CHECK(loaded.generation == 99 && slot == UINT_MAX);
    CHECK(nxs_storage_save(&io, &second) == NXS_RESULT_STORAGE_FAILED);
    CHECK(flash.erases == 0 && flash.programs == 0);
    CHECK(nxs_storage_read(NULL, &loaded, &slot) == NXS_STORAGE_READ_FAILED);
    CHECK(nxs_storage_read(&io, NULL, &slot) == NXS_STORAGE_READ_FAILED);
    CHECK(nxs_storage_read(&io, &loaded, NULL) == NXS_STORAGE_READ_FAILED);
    CHECK(nxs_storage_save(NULL, &second) == NXS_RESULT_STORAGE_UNAVAILABLE);
    CHECK(nxs_storage_save(&io, NULL) == NXS_RESULT_INVALID_PARAMETERS);
    nxs_storage_io_t missing_writer = {.context = &flash, .read = fake_read};
    CHECK(nxs_storage_save(&missing_writer, &second) == NXS_RESULT_STORAGE_UNAVAILABLE);
}

static void interrupted_programs(void) {
    nxs_stored_state_t previous = make_state(10, -24.0f), next = make_state(11, -18.0f);
    for (size_t cut = 0; cut <= NXS_STORAGE_RECORD_BYTES; ++cut) {
        fake_flash_t flash;
        fake_init(&flash);
        seed(&flash, 0, &previous);
        uint8_t previous_sector[NXS_STORAGE_SECTOR_BYTES];
        memcpy(previous_sector, flash.sectors[0], sizeof(previous_sector));
        flash.program_budget = cut;
        nxs_storage_io_t io = fake_io(&flash);
        CHECK(nxs_storage_save(&io, &next) == (cut == NXS_STORAGE_RECORD_BYTES ? NXS_RESULT_OK : NXS_RESULT_STORAGE_FAILED));
        CHECK(memcmp(previous_sector, flash.sectors[0], sizeof(previous_sector)) == 0);
        nxs_stored_state_t restored;
        unsigned int slot;
        CHECK(nxs_storage_read(&io, &restored, &slot) == NXS_STORAGE_LOADED);
        CHECK(restored.generation == previous.generation || restored.generation == next.generation);
        if (cut < NXS_STORAGE_PAGE_BYTES) {
            CHECK(restored.generation == previous.generation);
        }
        check_state(&restored, restored.generation == previous.generation ? &previous : &next);
    }
}

static void interrupted_erases(void) {
    nxs_stored_state_t oldest = make_state(9, -30.0f), previous = make_state(10, -24.0f), next = make_state(11, -18.0f);
    for (size_t cut = 0; cut <= NXS_STORAGE_SECTOR_BYTES; ++cut) {
        fake_flash_t flash;
        fake_init(&flash);
        seed(&flash, 0, &oldest);
        seed(&flash, 1, &previous);
        uint8_t previous_sector[NXS_STORAGE_SECTOR_BYTES];
        memcpy(previous_sector, flash.sectors[1], sizeof(previous_sector));
        flash.erase_budget = cut;
        nxs_storage_io_t io = fake_io(&flash);
        CHECK(nxs_storage_save(&io, &next) == (cut == NXS_STORAGE_SECTOR_BYTES ? NXS_RESULT_OK : NXS_RESULT_STORAGE_FAILED));
        CHECK(memcmp(previous_sector, flash.sectors[1], sizeof(previous_sector)) == 0);
        nxs_stored_state_t restored;
        unsigned int slot;
        CHECK(nxs_storage_read(&io, &restored, &slot) == NXS_STORAGE_LOADED);
        check_state(&restored, cut == NXS_STORAGE_SECTOR_BYTES ? &next : &previous);
    }
}

static void io_failures_and_media_changes(void) {
    nxs_stored_state_t previous = make_state(10, -24.0f), next = make_state(11, -18.0f);
    for (unsigned int failure = 1; failure <= 8; ++failure) {
        fake_flash_t flash;
        fake_init(&flash);
        seed(&flash, 0, &previous);
        flash.fail_call = failure;
        nxs_storage_io_t io = fake_io(&flash);
        CHECK(nxs_storage_save(&io, &next) == NXS_RESULT_STORAGE_FAILED);
        flash.fail_call = 0;
        nxs_stored_state_t restored;
        unsigned int slot;
        CHECK(nxs_storage_read(&io, &restored, &slot) == NXS_STORAGE_LOADED);
        check_state(&restored, failure == 8 ? &next : &previous);
    }
    for (unsigned int mode = 0; mode < 3; ++mode) {
        fake_flash_t flash;
        fake_init(&flash);
        nxs_stored_state_t oldest = make_state(9, -30.0f);
        seed(&flash, 0, &previous);
        seed(&flash, 1, &oldest);
        flash.silent_erase_failure = mode == 0;
        flash.corrupt_data = mode == 1;
        flash.corrupt_commit = mode == 2;
        nxs_storage_io_t io = fake_io(&flash);
        CHECK(nxs_storage_save(&io, &next) == NXS_RESULT_STORAGE_FAILED);
        CHECK(flash.programs == mode);
        nxs_stored_state_t restored;
        unsigned int slot;
        CHECK(nxs_storage_read(&io, &restored, &slot) == NXS_STORAGE_LOADED && slot == 0);
        check_state(&restored, &previous);
    }
    fake_flash_t flash;
    fake_init(&flash);
    seed(&flash, 0, &previous);
    seed(&flash, 1, &next);
    flash.sectors[1][0] ^= 1u;
    nxs_stored_state_t newer = make_state(12, -12.0f);
    nxs_storage_io_t io = fake_io(&flash);
    CHECK(nxs_storage_save(&io, &newer) == NXS_RESULT_OK);
    CHECK(flash.last_erased == 1);
    nxs_storage_record_t original_record;
    CHECK(nxs_storage_record_encode(&previous, &original_record));
    CHECK(memcmp(flash.sectors[0], original_record.bytes, sizeof(original_record.bytes)) == 0);
    nxs_stored_state_t restored;
    unsigned int slot;
    CHECK(nxs_storage_read(&io, &restored, &slot) == NXS_STORAGE_LOADED && slot == 1);
    check_state(&restored, &newer);
}

static void device_name_persistence(void) {
    fake_flash_t flash;
    fake_init(&flash);
    nxs_storage_io_t io = fake_io(&flash);
    nxs_stored_state_t named = make_state(1, -18.0f);
    strcpy(named.device_name, "Bedroom SoundBox");
    CHECK(nxs_storage_save(&io, &named) == NXS_RESULT_OK);
    nxs_stored_state_t restored;
    unsigned int slot;
    CHECK(nxs_storage_read(&io, &restored, &slot) == NXS_STORAGE_LOADED);
    check_state(&restored, &named);

    nxs_stored_state_t renamed = make_state(2, -18.0f);
    strcpy(renamed.device_name, "Office SoundBox");
    CHECK(nxs_storage_save(&io, &renamed) == NXS_RESULT_OK);
    CHECK(nxs_storage_read(&io, &restored, &slot) == NXS_STORAGE_LOADED);
    check_state(&restored, &renamed);

    nxs_stored_state_t cleared = make_state(3, -18.0f);
    CHECK(nxs_storage_save(&io, &cleared) == NXS_RESULT_OK);
    CHECK(nxs_storage_read(&io, &restored, &slot) == NXS_STORAGE_LOADED);
    check_state(&restored, &cleared);

    nxs_stored_state_t invalid_name = make_state(4, -18.0f);
    invalid_name.device_name[0] = '\n';
    nxs_storage_record_t record;
    CHECK(!nxs_storage_record_encode(&invalid_name, &record));
}

int main(void) {
    record_validation();
    selection_and_generation();
    interrupted_programs();
    interrupted_erases();
    io_failures_and_media_changes();
    device_name_persistence();
    return nxs_test_finish("Recoverable storage");
}
