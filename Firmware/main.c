#include "nxs_engine.h"
#include "nxs_flash_storage.h"
#include "nxs_usb.h"

#include "hardware/clocks.h"
#include "hardware/watchdog.h"
#include "pico/bootrom.h"
#include "pico/stdlib.h"
#include "pico/unique_id.h"
#include "tusb.h"

int main(void) {
    if (!set_sys_clock_khz(NXS_SYSTEM_CLOCK_HZ / 1000u, true) || clock_get_hz(clk_sys) != NXS_SYSTEM_CLOCK_HZ) {
        panic("NeXTsound requires 150 MHz");
    }
    static char serial[PICO_UNIQUE_BOARD_ID_SIZE_BYTES * 2 + 1];
    pico_get_unique_board_id_string(serial, sizeof(serial));
    (void)nxs_flash_storage_init();
    const nxs_flash_geometry_t *geometry = nxs_flash_storage_geometry();
    const nxs_storage_io_t *storage = nxs_flash_storage_io();
    nxs_stored_state_t restored;
    unsigned int slot;
    nxs_storage_load_result_t loaded = nxs_storage_read(storage, &restored, &slot);
    const nxs_stored_state_t *saved = loaded == NXS_STORAGE_LOADED ? &restored : NULL;
    if (!nxs_audio_engine_init(saved ? &saved->snapshot : NULL)) {
        panic("Audio owner initialization failed");
    }
    bool writable = nxs_flash_storage_writable() && (loaded == NXS_STORAGE_LOADED || loaded == NXS_STORAGE_EMPTY);
    if (!nxs_usb_init(serial, NXS_FIRMWARE_VERSION) ||
        !nxs_usb_configure_storage(writable ? storage : NULL, geometry ? geometry->flash_size_bytes : 0, saved)) {
        panic("Invalid NeXTsound initialization");
    }
    tusb_rhport_init_t usb = {.role = TUSB_ROLE_DEVICE, .speed = TUSB_SPEED_FULL};
    if (!tusb_init(0, &usb)) {
        panic("USB initialization failed");
    }
    for (;;) {
        nxs_usb_task();
        tud_task();
        nxs_usb_reset_request_t reset = nxs_usb_pending_reset();
        if (reset.action != NXS_USB_RESET_NONE && nxs_audio_engine_maintenance_ready()) {
            if (reset.action == NXS_USB_RESET_BOOTSEL) {
                rom_reset_usb_boot_extra(-1, reset.disable_mask, false);
            } else {
                watchdog_reboot(0, 0, 0);
            }
            for (;;) {
                tight_loop_contents();
            }
        }
    }
}
