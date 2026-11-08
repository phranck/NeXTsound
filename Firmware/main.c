/** @file main.c
 * @brief Starts the firmware and services USB and status tasks on core 0.
 */

#include "nxs_engine.h"
#include "nxs_flash_storage.h"
#include "nxs_status_led.h"
#include "nxs_usb.h"

#include "hardware/clocks.h"
#include "hardware/watchdog.h"
#include "pico/bootrom.h"
#include "pico/stdlib.h"
#include "pico/unique_id.h"
#include "tusb.h"

/** @brief Fatal error for an invalid system clock. */
static const char clock_error[] = "NeXTsound requires 150 MHz";
/** @brief Fatal error for a failed status LED initialization. */
static const char status_led_error[] = "Status LED initialization failed";
/** @brief Fatal error for a failed audio owner initialization. */
static const char audio_error[] = "Audio owner initialization failed";
/** @brief Fatal error for invalid device or storage initialization. */
static const char device_error[] = "Invalid NeXTsound initialization";
/** @brief Fatal error for a failed TinyUSB initialization. */
static const char usb_error[] = "USB initialization failed";

/** @brief Initializes the board and runs the firmware's control loop.
 * @return This function does not return during normal operation.
 */
int main(void) {
    if (!set_sys_clock_khz(NXS_SYSTEM_CLOCK_HZ / 1000u, true) || clock_get_hz(clk_sys) != NXS_SYSTEM_CLOCK_HZ) {
        panic(clock_error);
    }
    if (!nxs_status_led_init()) {
        panic(status_led_error);
    }
    /** @brief USB serial string derived from the unique board ID. */
    static char serial[PICO_UNIQUE_BOARD_ID_SIZE_BYTES * 2 + 1] = {0};
    pico_get_unique_board_id_string(serial, sizeof(serial));
    (void)nxs_flash_storage_init();
    /** @brief Verified flash geometry used for persistent storage. */
    const nxs_flash_geometry_t *geometry = nxs_flash_storage_geometry();
    /** @brief Flash-backed storage interface. */
    const nxs_storage_io_t *storage = nxs_flash_storage_io();
    /** @brief Stored state read during boot, or zero when no record loads. */
    nxs_stored_state_t restored = {0};
    /** @brief Storage slot from which restored was loaded. */
    unsigned int slot = 0;
    /** @brief Result of loading the newest valid storage record. */
    nxs_storage_load_result_t loaded = nxs_storage_read(storage, &restored, &slot);
    /** @brief Loaded state used for boot, or NULL when no valid state exists. */
    const nxs_stored_state_t *saved = loaded == NXS_STORAGE_LOADED ? &restored : NULL;
    if (!nxs_audio_engine_init(saved ? &saved->snapshot : NULL)) {
        panic(audio_error);
    }
    /** @brief Whether verified storage accepts persistent writes. */
    const bool writable = nxs_flash_storage_writable() && (loaded == NXS_STORAGE_LOADED || loaded == NXS_STORAGE_EMPTY);
    if (!nxs_usb_init(serial, NXS_FIRMWARE_VERSION) ||
        !nxs_usb_configure_storage(writable ? storage : NULL, geometry ? geometry->flash_size_bytes : 0, saved)) {
        panic(device_error);
    }
    /** @brief TinyUSB device-mode initialization settings. */
    tusb_rhport_init_t usb = {.role = TUSB_ROLE_DEVICE, .speed = TUSB_SPEED_FULL};
    if (!tusb_init(0, &usb)) {
        panic(usb_error);
    }
    (void)nxs_status_led_ready();
    for (;;) {
        nxs_usb_task();
        tud_task();
        /** @brief Reset action requested through USB and awaiting audio quiescence. */
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
