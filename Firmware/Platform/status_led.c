/** @file status_led.c
 * @brief Implements nonblocking WS2812 boot status updates on core 0.
 */

#include "nxs_status_led.h"

#include "hardware/pio.h"
// The SDK-generated initializer implicitly converts the system clock and cycle count to float.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wconversion"
#include "ws2812.pio.h"
#pragma GCC diagnostic pop

/** @brief WS2812 bit frequency expected by the PIO program. */
#define NXS_WS2812_BIT_FREQUENCY_HZ 800000.0f
/** @brief Number of GPIO pins used by one WS2812. */
#define NXS_WS2812_PIN_COUNT 1u

// Core 0 owns all state in this module after nxs_status_led_init succeeds.
/** @brief PIO instance that drives the status LED. */
static PIO status_pio = NULL;
/** @brief State machine that drives the status LED. */
static unsigned int status_state_machine = 0;
/** @brief Instruction offset of the WS2812 program. */
static unsigned int status_program_offset = 0;

/** @brief Writes one status color to the PIO FIFO.
 * @param word The WS2812 color word in 0xGGRRBB00 format.
 * @return Always true after writing the word.
 */
static bool write_status_word(uint32_t word) {
    pio_sm_put(status_pio, status_state_machine, word);
    return true;
}

/** @brief Claims the onboard WS2812 and lights it dim red.
 * @return True when the PIO initialized and the boot color was written.
 */
bool nxs_status_led_init(void) {
    /** @brief Whether a free PIO state machine accepted the WS2812 program. */
    const bool claimed = pio_claim_free_sm_and_add_program_for_gpio_range(
        &ws2812_program, &status_pio, &status_state_machine, &status_program_offset, PICO_DEFAULT_WS2812_PIN, NXS_WS2812_PIN_COUNT, true);
    if (!claimed) {
        return false;
    }
    ws2812_program_init(status_pio, status_state_machine, status_program_offset, PICO_DEFAULT_WS2812_PIN, NXS_WS2812_BIT_FREQUENCY_HZ,
                        false);
    return write_status_word(NXS_STATUS_BOOTING_WORD);
}

/** @brief Lights the onboard WS2812 dim green after firmware initialization.
 * @return True when the ready color was written.
 */
bool nxs_status_led_ready(void) {
    pio_sm_set_enabled(status_pio, status_state_machine, false);
    pio_sm_clear_fifos(status_pio, status_state_machine);
    ws2812_program_init(status_pio, status_state_machine, status_program_offset, PICO_DEFAULT_WS2812_PIN, NXS_WS2812_BIT_FREQUENCY_HZ,
                        false);
    return write_status_word(NXS_STATUS_READY_WORD);
}
