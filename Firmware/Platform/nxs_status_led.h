/** @file nxs_status_led.h
 * @brief Drives the onboard WS2812 status LED.
 */

/** @brief Include guard for the status LED interface. */
#ifndef NXS_STATUS_LED_H
#define NXS_STATUS_LED_H

#include <stdbool.h>
#include <stdint.h>

/** @brief WS2812 word for the dim red boot status. */
#define NXS_STATUS_BOOTING_WORD 0x04000000u
/** @brief WS2812 word for the dim green ready status. */
#define NXS_STATUS_READY_WORD 0x00040000u
/** @brief Minimum delay between the red and green WS2812 frames. */
#define NXS_STATUS_READY_DELAY_US 1000000u

/** @brief Claims the onboard WS2812 and lights it dim red.
 * @return True when the PIO initialized and the boot color was written.
 */
bool nxs_status_led_init(void);

/** @brief Lights the onboard WS2812 dim green after firmware initialization.
 * @return True when the ready color was written without waiting.
 */
bool nxs_status_led_ready(void);

#endif
