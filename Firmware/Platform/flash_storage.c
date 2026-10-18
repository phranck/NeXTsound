#include "nxs_engine.h"
#include "nxs_flash_storage.h"

#include "hardware/flash.h"
#include "hardware/regs/addressmap.h"
#include "hardware/sync.h"
#include "pico/flash.h"
#include "pico/stdlib.h"

#include <string.h>

#if PICO_NO_FLASH || PICO_RP2040 || !PICO_FLASH_SAFE_EXECUTE_PICO_SUPPORT_MULTICORE_LOCKOUT || PICO_FLASH_ASSUME_CORE0_SAFE ||             \
    PICO_FLASH_ASSUME_CORE1_SAFE
#error "Persistent writes require an RP2350 flash image and explicit multicore lockout"
#endif

#define NXS_FLASH_LOCKOUT_TIMEOUT_MS 1000u

_Static_assert(FLASH_PAGE_SIZE == NXS_STORAGE_PAGE_BYTES, "SDK page alignment must match storage layout");
_Static_assert(FLASH_SECTOR_SIZE == NXS_STORAGE_SECTOR_BYTES, "SDK sector alignment must match storage layout");

extern uint8_t __flash_binary_end[];
extern uint8_t __nxs_storage_start[];

static nxs_flash_geometry_t geometry;
static bool geometry_valid;
static bool lockout_failed;

typedef struct {
    uint32_t offset;
    const uint8_t *bytes;
    bool erase;
} flash_operation_t;

static void __no_inline_not_in_flash_func(run_operation)(void *context) {
    const flash_operation_t *operation = context;
    if (operation->erase) {
        flash_range_erase(operation->offset, NXS_STORAGE_SECTOR_BYTES);
    } else {
        flash_range_program(operation->offset, operation->bytes, NXS_STORAGE_PAGE_BYTES);
    }
}

bool nxs_flash_storage_init(void) {
    if (get_core_num() != 0) {
        return false;
    }
    geometry_valid = false;
    lockout_failed = false;
    uint8_t identity[4] = {0x9f};
    uint8_t metadata[NXS_FLASH_SFDP_BYTES + 5u] = {0x5a};
    uint32_t interrupts = save_and_disable_interrupts();
    flash_do_cmd(identity, identity, sizeof(identity));
    flash_do_cmd(metadata, metadata, sizeof(metadata));
    restore_interrupts(interrupts);
    uintptr_t end = (uintptr_t)__flash_binary_end;
    if (end < XIP_BASE || end - XIP_BASE > UINT32_MAX ||
        !nxs_flash_geometry_decode(identity + 1, metadata + 5, NXS_FLASH_SFDP_BYTES, (uint32_t)(end - XIP_BASE), &geometry) ||
        (uintptr_t)__nxs_storage_start != XIP_BASE + geometry.slot_offsets[0]) {
        return false;
    }
    geometry_valid = true;
    return true;
}

const nxs_flash_geometry_t *nxs_flash_storage_geometry(void) {
    return geometry_valid ? &geometry : NULL;
}

bool nxs_flash_storage_writable(void) {
    return geometry_valid && !lockout_failed && nxs_audio_engine_flash_ready();
}

static bool read_slot(void *context, unsigned int slot, nxs_storage_record_t *record) {
    (void)context;
    if (!geometry_valid || slot >= NXS_STORAGE_SLOT_COUNT || !record) {
        return false;
    }
    memcpy(record->bytes, (const void *)(uintptr_t)(XIP_BASE + geometry.slot_offsets[slot]), sizeof(record->bytes));
    return true;
}

static bool execute(flash_operation_t *operation) {
    if (get_core_num() != 0 || !nxs_flash_storage_writable() || !nxs_audio_engine_maintenance_ready()) {
        return false;
    }
    int result = flash_safe_execute(run_operation, operation, NXS_FLASH_LOCKOUT_TIMEOUT_MS);
    if (result != PICO_OK) {
        lockout_failed = true;
    }
    return result == PICO_OK;
}

static bool erase_slot(void *context, unsigned int slot) {
    (void)context;
    if (!geometry_valid || slot >= NXS_STORAGE_SLOT_COUNT) {
        return false;
    }
    flash_operation_t operation = {.offset = geometry.slot_offsets[slot], .erase = true};
    return execute(&operation);
}

static bool program_page(void *context, unsigned int slot, unsigned int page, const uint8_t bytes[NXS_STORAGE_PAGE_BYTES]) {
    (void)context;
    uintptr_t address = (uintptr_t)bytes;
    if (!geometry_valid || slot >= NXS_STORAGE_SLOT_COUNT || page > NXS_STORAGE_COMMIT_PAGE || address < SRAM_BASE ||
        address > SRAM_END - NXS_STORAGE_PAGE_BYTES) {
        return false;
    }
    flash_operation_t operation = {.offset = geometry.slot_offsets[slot] + page * NXS_STORAGE_PAGE_BYTES, .bytes = bytes};
    return execute(&operation);
}

const nxs_storage_io_t *nxs_flash_storage_io(void) {
    static const nxs_storage_io_t io = {.read = read_slot, .erase = erase_slot, .program = program_page};
    return geometry_valid ? &io : NULL;
}
