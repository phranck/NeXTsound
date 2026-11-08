/** @file ws2812.pio.h
 * @brief Host fixture for the SDK's WS2812 program initializer.
 */

/** @brief Include guard for the fake WS2812 program. */
#ifndef TEST_WS2812_PIO_H
#define TEST_WS2812_PIO_H

#include "hardware/pio.h"

/** @brief Fake WS2812 program descriptor. */
static const pio_program_t ws2812_program = {0};

/** @brief Initializes the fake WS2812 program without touching hardware.
 * @param pio The unused fake PIO instance.
 * @param sm The unused fake state machine index.
 * @param offset The unused fake program offset.
 * @param pin The unused fake GPIO.
 * @param freq The unused fake bit frequency.
 * @param rgbw Whether the fake program uses RGBW, unused by the fixture.
 */
static inline void ws2812_program_init(PIO pio, uint sm, uint offset, uint pin, float freq, bool rgbw) {
    (void)pio;
    (void)sm;
    (void)offset;
    (void)pin;
    (void)freq;
    (void)rgbw;
}

#endif
