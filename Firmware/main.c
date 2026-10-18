#include "nxs_engine.h"
#include "nxs_usb.h"

#include "hardware/clocks.h"
#include "pico/stdlib.h"
#include "pico/unique_id.h"
#include "tusb.h"

int main(void) {
    if (!set_sys_clock_khz(NXS_SYSTEM_CLOCK_HZ / 1000u, true) || clock_get_hz(clk_sys) != NXS_SYSTEM_CLOCK_HZ) {
        panic("NeXTsound requires 150 MHz");
    }
    static char serial[PICO_UNIQUE_BOARD_ID_SIZE_BYTES * 2 + 1];
    pico_get_unique_board_id_string(serial, sizeof(serial));
    nxs_audio_engine_init();
    if (!nxs_usb_init(serial, NXS_FIRMWARE_VERSION)) {
        panic("Invalid NeXTsound identity");
    }
    tusb_rhport_init_t usb = {.role = TUSB_ROLE_DEVICE, .speed = TUSB_SPEED_FULL};
    if (!tusb_init(0, &usb)) {
        panic("USB initialization failed");
    }
    for (;;) {
        nxs_usb_task();
        tud_task();
    }
}
