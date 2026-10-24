#ifndef NXS_STORAGE_H
#define NXS_STORAGE_H

#include "nxs_protocol.h"
#include "nxs_storage_layout.h"

/** The format every save writes. Format 1 records, which carry no owner metadata, still decode. */
#define NXS_STORAGE_VERSION 2u
#define NXS_STORAGE_DATA_PAGE 0u
#define NXS_STORAGE_COMMIT_PAGE 1u
/** Holds the owner's note in format 2, and stays erased in format 1. */
#define NXS_STORAGE_NOTE_PAGE 2u

typedef struct {
    uint8_t bytes[NXS_STORAGE_RECORD_BYTES];
} nxs_storage_record_t;

typedef struct {
    nxs_snapshot_t snapshot;
    uint32_t generation;
    /** Empty when no custom name is stored; see NXS_OPERATION_SET_NAME. */
    char device_name[NXS_DEVICE_NAME_LENGTH];
    /** All zero when the record carries no metadata, as every format-1 record does. */
    nxs_owner_metadata_t metadata;
} nxs_stored_state_t;

typedef enum { NXS_STORAGE_EMPTY, NXS_STORAGE_LOADED, NXS_STORAGE_AMBIGUOUS, NXS_STORAGE_READ_FAILED } nxs_storage_load_result_t;

/** Callbacks address two isolated sectors, never arbitrary flash offsets. True means the full operation completed. */
typedef struct {
    void *context;
    bool (*read)(void *context, unsigned int slot, nxs_storage_record_t *record);
    bool (*erase)(void *context, unsigned int slot);
    bool (*program)(void *context, unsigned int slot, unsigned int page, const uint8_t bytes[NXS_STORAGE_PAGE_BYTES]);
} nxs_storage_io_t;

/**
 * Failure leaves destinations unchanged. Generation zero and unknown format/protocol versions are invalid.
 * Encoding writes format 2; decoding accepts formats 1 and 2.
 */
bool nxs_storage_record_encode(const nxs_stored_state_t *state, nxs_storage_record_t *record);
bool nxs_storage_record_decode(const nxs_storage_record_t *record, nxs_stored_state_t *state);
/** Only LOADED changes state and slot. Equal generations with different valid contents are ambiguous. */
nxs_storage_load_result_t nxs_storage_read(const nxs_storage_io_t *io, nxs_stored_state_t *state, unsigned int *slot);
/** Rescan before every save so a newly corrupted latest slot cannot cause the remaining valid slot to be erased. */
nxs_result_t nxs_storage_save(const nxs_storage_io_t *io, const nxs_stored_state_t *state);

#endif
