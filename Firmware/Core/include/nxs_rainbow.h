/** @file nxs_rainbow.h
 * @brief Calculates the dim rainbow colors for the onboard status LED.
 */

/** @brief Include guard for the rainbow color interface. */
#ifndef NXS_RAINBOW_H
#define NXS_RAINBOW_H

#include <stdint.h>

/** @brief Returns the status LED color for an elapsed time.
 * @param elapsed_ms Milliseconds since the rainbow animation started.
 * @return The dim RGB color in 0x00RRGGBB format.
 */
uint32_t nxs_rainbow_color(uint64_t elapsed_ms);

/** @brief Converts an RGB color to one WS2812 PIO FIFO word.
 * @param color The RGB color in 0x00RRGGBB format.
 * @return The color in 0xGGRRBB00 format for the WS2812 program.
 */
uint32_t nxs_rainbow_ws2812_word(uint32_t color);

#endif
