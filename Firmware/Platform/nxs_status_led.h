/** @file nxs_status_led.h
 * @brief Drives the onboard WS2812 status LED.
 */

/** @brief Include guard for the status LED interface. */
#ifndef NXS_STATUS_LED_H
#define NXS_STATUS_LED_H

#include <stdbool.h>

/** @brief Claims and initializes the onboard WS2812.
 * @return True when the PIO program and state machine were initialized.
 */
bool nxs_status_led_init(void);

/** @brief Publishes the current rainbow color without waiting for the PIO FIFO. */
void nxs_status_led_task(void);

#endif
