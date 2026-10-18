#include "nxs_storage.h"

#include <string.h>

#define NXS_STORAGE_HEADER_BYTES 16u
#define NXS_STORAGE_CHECKSUM_OFFSET (NXS_STORAGE_PAGE_BYTES - 4u)
#define NXS_STORAGE_COMMIT_HEADER_BYTES 16u

_Static_assert(NXS_STORAGE_HEADER_BYTES + NXS_SNAPSHOT_SIZE <= NXS_STORAGE_CHECKSUM_OFFSET, "Snapshot must fit in one data page");
_Static_assert(NXS_STORAGE_RECORD_BYTES <= NXS_STORAGE_SECTOR_BYTES, "Records must fit in isolated sectors");

static const uint8_t data_magic[] = {'N', 'X', 'S', 'P'};
static const uint8_t commit_magic[] = {'N', 'X', 'S', 'C'};

static uint16_t read_u16(const uint8_t *bytes) {
    return (uint16_t)((uint16_t)bytes[0] | (uint16_t)((uint16_t)bytes[1] << 8));
}

static uint32_t read_u32(const uint8_t *bytes) {
    uint32_t value = 0;
    for (size_t index = 0; index < 4; ++index) {
        value |= (uint32_t)bytes[index] << (8u * index);
    }
    return value;
}

static void write_u16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
}

static void write_u32(uint8_t *bytes, uint32_t value) {
    for (size_t index = 0; index < 4; ++index) {
        bytes[index] = (uint8_t)(value >> (8u * index));
    }
}

static uint32_t checksum(const uint8_t *bytes, size_t length) {
    uint32_t value = UINT32_MAX;
    for (size_t index = 0; index < length; ++index) {
        value ^= bytes[index];
        for (unsigned int bit = 0; bit < 8; ++bit) {
            value = (value >> 1) ^ ((0u - (value & 1u)) & 0xedb88320u);
        }
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

bool nxs_storage_record_encode(const nxs_stored_state_t *state, nxs_storage_record_t *record) {
    if (!state || !record || state->generation == 0 || !nxs_snapshot_is_valid(&state->snapshot)) {
        return false;
    }
    nxs_storage_record_t candidate;
    memset(&candidate, 0xff, sizeof(candidate));
    memcpy(candidate.bytes, data_magic, sizeof(data_magic));
    write_u16(candidate.bytes + 4, NXS_STORAGE_VERSION);
    write_u16(candidate.bytes + 6, NXS_STORAGE_PAGE_BYTES);
    write_u32(candidate.bytes + 8, state->generation);
    candidate.bytes[12] = NXS_SNAPSHOT_PROTOCOL_MAJOR;
    candidate.bytes[13] = NXS_SNAPSHOT_PROTOCOL_MINOR;
    write_u16(candidate.bytes + 14, NXS_SNAPSHOT_SIZE);
    if (nxs_snapshot_encode(&state->snapshot, candidate.bytes + NXS_STORAGE_HEADER_BYTES, NXS_SNAPSHOT_SIZE) != NXS_RESULT_OK) {
        return false;
    }
    uint32_t digest = checksum(candidate.bytes, NXS_STORAGE_CHECKSUM_OFFSET);
    write_u32(candidate.bytes + NXS_STORAGE_CHECKSUM_OFFSET, digest);
    uint8_t *commit = candidate.bytes + NXS_STORAGE_PAGE_BYTES;
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
    const uint8_t *commit = bytes + NXS_STORAGE_PAGE_BYTES;
    uint32_t generation = read_u32(bytes + 8);
    uint32_t digest = read_u32(bytes + NXS_STORAGE_CHECKSUM_OFFSET);
    size_t padding_start = NXS_STORAGE_HEADER_BYTES + NXS_SNAPSHOT_SIZE;
    if (memcmp(bytes, data_magic, sizeof(data_magic)) != 0 || read_u16(bytes + 4) != NXS_STORAGE_VERSION ||
        read_u16(bytes + 6) != NXS_STORAGE_PAGE_BYTES || generation == 0 || bytes[12] != NXS_SNAPSHOT_PROTOCOL_MAJOR ||
        bytes[13] != NXS_SNAPSHOT_PROTOCOL_MINOR || read_u16(bytes + 14) != NXS_SNAPSHOT_SIZE ||
        !all_erased(bytes + padding_start, NXS_STORAGE_CHECKSUM_OFFSET - padding_start) ||
        checksum(bytes, NXS_STORAGE_CHECKSUM_OFFSET) != digest || memcmp(commit, commit_magic, sizeof(commit_magic)) != 0 ||
        read_u32(commit + 4) != generation || read_u32(commit + 8) != digest || read_u32(commit + 12) != ~digest ||
        !all_erased(commit + NXS_STORAGE_COMMIT_HEADER_BYTES, NXS_STORAGE_PAGE_BYTES - NXS_STORAGE_COMMIT_HEADER_BYTES)) {
        return false;
    }
    nxs_stored_state_t candidate = {.generation = generation};
    if (nxs_snapshot_decode(bytes + NXS_STORAGE_HEADER_BYTES, NXS_SNAPSHOT_SIZE, &candidate.snapshot) != NXS_RESULT_OK) {
        return false;
    }
    *state = candidate;
    return true;
}

nxs_storage_load_result_t nxs_storage_read(const nxs_storage_io_t *io, nxs_stored_state_t *state, unsigned int *slot) {
    if (!io || !io->read || !state || !slot) {
        return NXS_STORAGE_READ_FAILED;
    }
    nxs_storage_record_t records[NXS_STORAGE_SLOT_COUNT];
    nxs_stored_state_t states[NXS_STORAGE_SLOT_COUNT];
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

nxs_result_t nxs_storage_save(const nxs_storage_io_t *io, const nxs_stored_state_t *state) {
    nxs_storage_record_t expected;
    if (!nxs_storage_record_encode(state, &expected)) {
        return NXS_RESULT_INVALID_PARAMETERS;
    }
    if (!io || !io->read || !io->erase || !io->program) {
        return NXS_RESULT_STORAGE_UNAVAILABLE;
    }
    nxs_stored_state_t previous;
    unsigned int active_slot = 0;
    nxs_storage_load_result_t loaded = nxs_storage_read(io, &previous, &active_slot);
    if (loaded == NXS_STORAGE_READ_FAILED || loaded == NXS_STORAGE_AMBIGUOUS) {
        return NXS_RESULT_STORAGE_FAILED;
    }
    nxs_storage_record_t readback;
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
    if (!io->erase(io->context, target) || !io->read(io->context, target, &readback) ||
        !all_erased(readback.bytes, sizeof(readback.bytes)) || !io->program(io->context, target, NXS_STORAGE_DATA_PAGE, expected.bytes) ||
        !io->read(io->context, target, &readback) || memcmp(readback.bytes, expected.bytes, NXS_STORAGE_PAGE_BYTES) != 0 ||
        !all_erased(readback.bytes + NXS_STORAGE_PAGE_BYTES, NXS_STORAGE_PAGE_BYTES) ||
        !io->program(io->context, target, NXS_STORAGE_COMMIT_PAGE, expected.bytes + NXS_STORAGE_PAGE_BYTES) ||
        !io->read(io->context, target, &readback)) {
        return NXS_RESULT_STORAGE_FAILED;
    }
    nxs_stored_state_t decoded;
    return memcmp(&readback, &expected, sizeof(expected)) == 0 && nxs_storage_record_decode(&readback, &decoded)
               ? NXS_RESULT_OK
               : NXS_RESULT_STORAGE_FAILED;
}
