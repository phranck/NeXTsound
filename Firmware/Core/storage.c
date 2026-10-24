#include "nxs_storage.h"

#include <string.h>

#define NXS_STORAGE_FORMAT_1 1u
#define NXS_STORAGE_HEADER_BYTES 16u
#define NXS_STORAGE_CHECKSUM_OFFSET (NXS_STORAGE_PAGE_BYTES - 4u)
#define NXS_STORAGE_COMMIT_HEADER_BYTES 16u
#define NXS_STORAGE_NAME_OFFSET (NXS_STORAGE_HEADER_BYTES + NXS_SNAPSHOT_SIZE)
/** Format 1 ends after the device name; format 2 continues with the owner metadata in the same page. */
#define NXS_STORAGE_FORMAT_1_END (NXS_STORAGE_NAME_OFFSET + NXS_DEVICE_NAME_LENGTH)
#define NXS_STORAGE_DATE_OFFSET NXS_STORAGE_FORMAT_1_END
#define NXS_STORAGE_SERIAL_OFFSET (NXS_STORAGE_DATE_OFFSET + 4u)
#define NXS_STORAGE_SERIAL_BYTES 3u
/** Bit 0 is NXS_METADATA_FLAG_SERIAL_NUMBER; firmware 0.2.0 wrote 0 here and refuses any other value. */
#define NXS_STORAGE_FLAGS_OFFSET (NXS_STORAGE_SERIAL_OFFSET + NXS_STORAGE_SERIAL_BYTES)
#define NXS_STORAGE_OWNER_OFFSET (NXS_STORAGE_FLAGS_OFFSET + 1u)
#define NXS_STORAGE_FORMAT_2_END (NXS_STORAGE_OWNER_OFFSET + NXS_OWNER_NAME_LENGTH)

_Static_assert(NXS_STORAGE_FORMAT_2_END <= NXS_STORAGE_CHECKSUM_OFFSET,
               "Snapshot, device name, date, serial number and owner must fit in one data page");
_Static_assert(NXS_OWNER_NOTE_LENGTH == NXS_STORAGE_PAGE_BYTES, "The note fills the note page");
_Static_assert(NXS_SERIAL_NUMBER_MAX >> (8u * NXS_STORAGE_SERIAL_BYTES) == 0, "Every serial number fits its stored bytes");
_Static_assert(NXS_STORAGE_RECORD_BYTES <= NXS_STORAGE_SECTOR_BYTES, "Records must fit in isolated sectors");

static const uint8_t data_magic[] = {'N', 'X', 'S', 'P'};
static const uint8_t commit_magic[] = {'N', 'X', 'S', 'C'};

/** The commit page is written last, so a save interrupted at any point leaves no valid new record. */
static const unsigned int program_order[] = {NXS_STORAGE_DATA_PAGE, NXS_STORAGE_NOTE_PAGE, NXS_STORAGE_COMMIT_PAGE};
_Static_assert(sizeof(program_order) / sizeof(program_order[0]) == NXS_STORAGE_RECORD_PAGES, "Every record page is programmed");

static uint16_t read_u16(const uint8_t *bytes) {
    return (uint16_t)((uint16_t)bytes[0] | (uint16_t)((uint16_t)bytes[1] << 8));
}

static uint32_t read_unsigned(const uint8_t *bytes, size_t count) {
    uint32_t value = 0;
    for (size_t index = 0; index < count; ++index) {
        value |= (uint32_t)bytes[index] << (8u * index);
    }
    return value;
}

static uint32_t read_u32(const uint8_t *bytes) {
    return read_unsigned(bytes, 4);
}

static void write_u16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
}

static void write_unsigned(uint8_t *bytes, uint32_t value, size_t count) {
    for (size_t index = 0; index < count; ++index) {
        bytes[index] = (uint8_t)(value >> (8u * index));
    }
}

static void write_u32(uint8_t *bytes, uint32_t value) {
    write_unsigned(bytes, value, 4);
}

/** CRC-32 without its final inversion, so a checksum can continue across two pages. */
static uint32_t crc_update(uint32_t value, const uint8_t *bytes, size_t length) {
    for (size_t index = 0; index < length; ++index) {
        value ^= bytes[index];
        for (unsigned int bit = 0; bit < 8; ++bit) {
            value = (value >> 1) ^ ((0u - (value & 1u)) & 0xedb88320u);
        }
    }
    return value;
}

/** Format 1 covers the data page before its checksum; format 2 also covers the note page. */
static uint32_t record_checksum(const uint8_t *bytes, uint16_t format) {
    uint32_t value = crc_update(UINT32_MAX, bytes, NXS_STORAGE_CHECKSUM_OFFSET);
    if (format != NXS_STORAGE_FORMAT_1) {
        value = crc_update(value, bytes + NXS_STORAGE_NOTE_PAGE * NXS_STORAGE_PAGE_BYTES, NXS_STORAGE_PAGE_BYTES);
    }
    return ~value;
}

static bool all_erased(const uint8_t *bytes, size_t length) {
    for (size_t index = 0; index < length; ++index) {
        if (bytes[index] != 0xff) {
            return false;
        }
    }
    return true;
}

static const uint8_t *page_bytes(const nxs_storage_record_t *record, unsigned int page) {
    return record->bytes + page * NXS_STORAGE_PAGE_BYTES;
}

bool nxs_storage_record_encode(const nxs_stored_state_t *state, nxs_storage_record_t *record) {
    if (!state || !record || state->generation == 0 || !nxs_snapshot_is_valid(&state->snapshot) ||
        !nxs_owner_metadata_is_valid(&state->metadata)) {
        return false;
    }
    nxs_storage_record_t candidate;
    memset(&candidate, 0xff, sizeof(candidate));
    uint8_t *bytes = candidate.bytes;
    memcpy(bytes, data_magic, sizeof(data_magic));
    write_u16(bytes + 4, NXS_STORAGE_VERSION);
    write_u16(bytes + 6, NXS_STORAGE_PAGE_BYTES);
    write_u32(bytes + 8, state->generation);
    bytes[12] = NXS_SNAPSHOT_PROTOCOL_MAJOR;
    bytes[13] = NXS_SNAPSHOT_PROTOCOL_MINOR;
    write_u16(bytes + 14, NXS_SNAPSHOT_SIZE);
    if (nxs_snapshot_encode(&state->snapshot, bytes + NXS_STORAGE_HEADER_BYTES, NXS_SNAPSHOT_SIZE) != NXS_RESULT_OK ||
        nxs_device_name_encode(state->device_name, bytes + NXS_STORAGE_NAME_OFFSET, NXS_DEVICE_NAME_LENGTH) != NXS_RESULT_OK) {
        return false;
    }
    write_u32(bytes + NXS_STORAGE_DATE_OFFSET, state->metadata.date);
    write_unsigned(bytes + NXS_STORAGE_SERIAL_OFFSET, state->metadata.serial_number, NXS_STORAGE_SERIAL_BYTES);
    bytes[NXS_STORAGE_FLAGS_OFFSET] = state->metadata.has_serial_number ? NXS_METADATA_FLAG_SERIAL_NUMBER : 0u;
    memcpy(bytes + NXS_STORAGE_OWNER_OFFSET, state->metadata.owner, NXS_OWNER_NAME_LENGTH);
    memcpy(bytes + NXS_STORAGE_NOTE_PAGE * NXS_STORAGE_PAGE_BYTES, state->metadata.note, NXS_OWNER_NOTE_LENGTH);
    uint32_t digest = record_checksum(bytes, NXS_STORAGE_VERSION);
    write_u32(bytes + NXS_STORAGE_CHECKSUM_OFFSET, digest);
    uint8_t *commit = bytes + NXS_STORAGE_COMMIT_PAGE * NXS_STORAGE_PAGE_BYTES;
    memcpy(commit, commit_magic, sizeof(commit_magic));
    write_u32(commit + 4, state->generation);
    write_u32(commit + 8, digest);
    write_u32(commit + 12, ~digest);
    *record = candidate;
    return true;
}

bool nxs_storage_record_decode(const nxs_storage_record_t *record, nxs_stored_state_t *state) {
    if (!record || !state) {
        return false;
    }
    const uint8_t *bytes = record->bytes;
    const uint8_t *commit = page_bytes(record, NXS_STORAGE_COMMIT_PAGE);
    const uint8_t *note = page_bytes(record, NXS_STORAGE_NOTE_PAGE);
    uint16_t format = read_u16(bytes + 4);
    bool format_1 = format == NXS_STORAGE_FORMAT_1;
    uint32_t generation = read_u32(bytes + 8);
    uint32_t digest = read_u32(bytes + NXS_STORAGE_CHECKSUM_OFFSET);
    size_t padding_start = format_1 ? NXS_STORAGE_FORMAT_1_END : NXS_STORAGE_FORMAT_2_END;
    if (memcmp(bytes, data_magic, sizeof(data_magic)) != 0 || (!format_1 && format != NXS_STORAGE_VERSION) ||
        read_u16(bytes + 6) != NXS_STORAGE_PAGE_BYTES || generation == 0 || bytes[12] != NXS_SNAPSHOT_PROTOCOL_MAJOR ||
        bytes[13] != NXS_SNAPSHOT_PROTOCOL_MINOR || read_u16(bytes + 14) != NXS_SNAPSHOT_SIZE ||
        !all_erased(bytes + padding_start, NXS_STORAGE_CHECKSUM_OFFSET - padding_start) ||
        (format_1 ? !all_erased(note, NXS_STORAGE_PAGE_BYTES)
                  : (bytes[NXS_STORAGE_FLAGS_OFFSET] & ~NXS_METADATA_FLAG_SERIAL_NUMBER) != 0) ||
        record_checksum(bytes, format) != digest || memcmp(commit, commit_magic, sizeof(commit_magic)) != 0 ||
        read_u32(commit + 4) != generation || read_u32(commit + 8) != digest || read_u32(commit + 12) != ~digest ||
        !all_erased(commit + NXS_STORAGE_COMMIT_HEADER_BYTES, NXS_STORAGE_PAGE_BYTES - NXS_STORAGE_COMMIT_HEADER_BYTES)) {
        return false;
    }
    nxs_stored_state_t candidate = {.generation = generation};
    if (nxs_snapshot_decode(bytes + NXS_STORAGE_HEADER_BYTES, NXS_SNAPSHOT_SIZE, &candidate.snapshot) != NXS_RESULT_OK ||
        nxs_device_name_decode(bytes + NXS_STORAGE_NAME_OFFSET, NXS_DEVICE_NAME_LENGTH, candidate.device_name) != NXS_RESULT_OK) {
        return false;
    }
    if (!format_1) {
        candidate.metadata.date = read_u32(bytes + NXS_STORAGE_DATE_OFFSET);
        candidate.metadata.has_serial_number = (bytes[NXS_STORAGE_FLAGS_OFFSET] & NXS_METADATA_FLAG_SERIAL_NUMBER) != 0;
        candidate.metadata.serial_number = read_unsigned(bytes + NXS_STORAGE_SERIAL_OFFSET, NXS_STORAGE_SERIAL_BYTES);
        memcpy(candidate.metadata.owner, bytes + NXS_STORAGE_OWNER_OFFSET, NXS_OWNER_NAME_LENGTH);
        memcpy(candidate.metadata.note, note, NXS_OWNER_NOTE_LENGTH);
        if (!nxs_owner_metadata_is_valid(&candidate.metadata)) {
            return false;
        }
    }
    *state = candidate;
    return true;
}

/*
 * The records and states below are static because a record takes 768 bytes and its state about 500, while each core has
 * a 4 KiB stack and a save reads both slots. Storage runs only on the control core and never reentrantly.
 */
nxs_storage_load_result_t nxs_storage_read(const nxs_storage_io_t *io, nxs_stored_state_t *state, unsigned int *slot) {
    if (!io || !io->read || !state || !slot) {
        return NXS_STORAGE_READ_FAILED;
    }
    static nxs_storage_record_t records[NXS_STORAGE_SLOT_COUNT];
    static nxs_stored_state_t states[NXS_STORAGE_SLOT_COUNT];
    bool valid[NXS_STORAGE_SLOT_COUNT];
    for (unsigned int index = 0; index < NXS_STORAGE_SLOT_COUNT; ++index) {
        if (!io->read(io->context, index, &records[index])) {
            return NXS_STORAGE_READ_FAILED;
        }
        valid[index] = nxs_storage_record_decode(&records[index], &states[index]);
    }
    if (!valid[0] && !valid[1]) {
        return NXS_STORAGE_EMPTY;
    }
    unsigned int selected = valid[1] && (!valid[0] || states[1].generation > states[0].generation) ? 1u : 0u;
    if (valid[0] && valid[1] && states[0].generation == states[1].generation && memcmp(&records[0], &records[1], sizeof(records[0])) != 0) {
        return NXS_STORAGE_AMBIGUOUS;
    }
    *state = states[selected];
    *slot = selected;
    return NXS_STORAGE_LOADED;
}

/** Programmed pages must read back as encoded, and the pages still to come must read back erased. */
static bool readback_matches(const nxs_storage_record_t *readback, const nxs_storage_record_t *expected, size_t programmed_steps) {
    for (size_t step = 0; step < NXS_STORAGE_RECORD_PAGES; ++step) {
        unsigned int page = program_order[step];
        const uint8_t *actual = page_bytes(readback, page);
        bool matches = step < programmed_steps ? memcmp(actual, page_bytes(expected, page), NXS_STORAGE_PAGE_BYTES) == 0
                                               : all_erased(actual, NXS_STORAGE_PAGE_BYTES);
        if (!matches) {
            return false;
        }
    }
    return true;
}

nxs_result_t nxs_storage_save(const nxs_storage_io_t *io, const nxs_stored_state_t *state) {
    static nxs_storage_record_t expected;
    static nxs_storage_record_t readback;
    static nxs_stored_state_t previous;
    if (!nxs_storage_record_encode(state, &expected)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    if (!io || !io->read || !io->erase || !io->program) {
        return NXS_RESULT_STORAGE_UNAVAILABLE;
    }
    unsigned int active_slot = 0;
    nxs_storage_load_result_t loaded = nxs_storage_read(io, &previous, &active_slot);
    if (loaded == NXS_STORAGE_READ_FAILED || loaded == NXS_STORAGE_AMBIGUOUS) {
        return NXS_RESULT_STORAGE_FAILED;
    }
    if (loaded == NXS_STORAGE_LOADED) {
        if (state->generation < previous.generation) {
            return NXS_RESULT_STALE_GENERATION;
        }
        if (state->generation == previous.generation) {
            if (!nxs_storage_record_encode(&previous, &readback)) {
                return NXS_RESULT_STORAGE_FAILED;
            }
            return memcmp(&expected, &readback, sizeof(expected)) == 0 ? NXS_RESULT_OK : NXS_RESULT_STALE_GENERATION;
        }
    }
    unsigned int target = loaded == NXS_STORAGE_LOADED ? (active_slot + 1u) % NXS_STORAGE_SLOT_COUNT : 0u;
    if (!io->erase(io->context, target) || !io->read(io->context, target, &readback) || !readback_matches(&readback, &expected, 0)) {
        return NXS_RESULT_STORAGE_FAILED;
    }
    for (size_t step = 0; step < NXS_STORAGE_RECORD_PAGES; ++step) {
        unsigned int page = program_order[step];
        if (!io->program(io->context, target, page, page_bytes(&expected, page)) || !io->read(io->context, target, &readback) ||
            !readback_matches(&readback, &expected, step + 1)) {
            return NXS_RESULT_STORAGE_FAILED;
        }
    }
    nxs_stored_state_t decoded;
    return nxs_storage_record_decode(&readback, &decoded) ? NXS_RESULT_OK : NXS_RESULT_STORAGE_FAILED;
}
