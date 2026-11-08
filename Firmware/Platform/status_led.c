/** @file status_led.c
 * @brief Implements nonblocking WS2812 status updates on core 0.
 */

#include "nxs_status_led.h"

#include "nxs_rainbow.h"

#include "hardware/pio.h"
#include "pico/time.h"
// The SDK-generated initializer implicitly converts the system clock and cycle count to float.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wconversion"
#include "ws2812.pio.h"
#pragma GCC diagnostic pop

/** @brief WS2812 bit frequency expected by the PIO program. */
#define NXS_WS2812_BIT_FREQUENCY_HZ 800000.0f
/** @brief Number of GPIO pins used by one WS2812. */
#define NXS_WS2812_PIN_COUNT 1u
/** @brief Number of microseconds in one millisecond. */
#define NXS_MICROSECONDS_PER_MILLISECOND 1000u

// Core 0 owns all state in this module after nxs_status_led_init succeeds.
/** @brief PIO instance that drives the status LED. */
static PIO status_pio = NULL;
/** @brief State machine that drives the status LED. */
static unsigned int status_state_machine = 0;
/** @brief Instruction offset of the WS2812 program. */
static unsigned int status_program_offset = 0;
/** @brief Boot-relative start time of the animation. */
static uint64_t status_started_ms = 0;
/** @brief Last color written to the PIO FIFO. */
static uint32_t status_previous_color = 0;
/** @brief Whether status_previous_color holds a written color. */
static bool status_has_previous_color = false;

/** @brief Claims and initializes the onboard WS2812. */
bool nxs_status_led_init(void) {
    /** @brief Whether a free PIO state machine accepted the WS2812 program. */
    const bool claimed = pio_claim_free_sm_and_add_program_for_gpio_range(
        &ws2812_program, &status_pio, &status_state_machine, &status_program_offset, PICO_DEFAULT_WS2812_PIN, NXS_WS2812_PIN_COUNT, true);
    if (!claimed) {
        return false;
    }
    ws2812_program_init(status_pio, status_state_machine, status_program_offset, PICO_DEFAULT_WS2812_PIN, NXS_WS2812_BIT_FREQUENCY_HZ,
                        false);
    status_started_ms = to_us_since_boot(get_absolute_time()) / NXS_MICROSECONDS_PER_MILLISECOND;
    status_previous_color = 0;
    status_has_previous_color = false;
    return true;
}

/** @brief Publishes the current rainbow color without waiting for the PIO FIFO. */
void nxs_status_led_task(void) {
    /** @brief Time since the animation started. */
    const uint64_t elapsed_ms = (to_us_since_boot(get_absolute_time()) / NXS_MICROSECONDS_PER_MILLISECOND) - status_started_ms;
    /** @brief Current dim rainbow color. */
    const uint32_t color = nxs_rainbow_color(elapsed_ms);
    if ((status_has_previous_color && color == status_previous_color) || pio_sm_is_tx_fifo_full(status_pio, status_state_machine)) {
        return;
    }
    pio_sm_put(status_pio, status_state_machine, nxs_rainbow_ws2812_word(color));
    status_previous_color = color;
    status_has_previous_color = true;
}
