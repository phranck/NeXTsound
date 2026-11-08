/** @file pio.h
 * @brief Host fixture for the PIO calls used by the status LED driver.
 */

/** @brief Include guard for the fake PIO interface. */
#ifndef TEST_HARDWARE_PIO_H
#define TEST_HARDWARE_PIO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/** @brief SDK-compatible unsigned integer alias. */
typedef unsigned int uint;
/** @brief Fake PIO program descriptor. */
typedef struct {
    /** @brief Unused fixture field. */
    int unused;
} pio_program_t;
/** @brief Fake PIO hardware instance. */
typedef struct {
    /** @brief Unused fixture field. */
    int unused;
} pio_hw_t;
/** @brief Pointer to a fake PIO hardware instance. */
typedef pio_hw_t *PIO;

/** @brief GPIO used by the onboard WS2812. */
#define PICO_DEFAULT_WS2812_PIN 16u
/** @brief Maximum number of status words recorded by the fixture. */
#define TEST_MAX_STATUS_WORDS 4u
/** @brief Simulated duration of one 24-bit WS2812 frame at 800 kHz. */
#define TEST_WS2812_FRAME_US 30u

/** @brief Whether the fake PIO FIFO is full. */
extern bool fake_tx_fifo_full;
/** @brief WS2812 words written through the fake PIO. */
extern uint32_t fake_status_words[TEST_MAX_STATUS_WORDS];
/** @brief Number of WS2812 words written through the fake PIO. */
extern unsigned int fake_status_word_count;
/** @brief Current fake timestamp in microseconds. */
extern uint64_t fake_now_us;

/** @brief Claims a fake PIO state machine and installs the fake program.
 * @param program The unused fake program descriptor.
 * @param pio Receives the fake PIO instance.
 * @param sm Receives the fake state machine index.
 * @param offset Receives the fake program offset.
 * @param gpio_base The unused first GPIO.
 * @param gpio_count The unused GPIO count.
 * @param set_gpio_base Whether the GPIO base may change, unused by the fixture.
 * @return Always true.
 */
static inline bool pio_claim_free_sm_and_add_program_for_gpio_range(const pio_program_t *program, PIO *pio, uint *sm, uint *offset,
                                                                    uint gpio_base, uint gpio_count, bool set_gpio_base) {
    (void)program;
    (void)gpio_base;
    (void)gpio_count;
    (void)set_gpio_base;
    /** @brief Fake PIO instance returned by the fixture. */
    static pio_hw_t fake_pio;
    *pio = &fake_pio;
    *sm = 0;
    *offset = 0;
    return true;
}

/** @brief Reports the fake TX FIFO state.
 * @param pio The unused fake PIO instance.
 * @param sm The unused fake state machine index.
 * @return The value of fake_tx_fifo_full.
 */
static inline bool pio_sm_is_tx_fifo_full(PIO pio, uint sm) {
    (void)pio;
    (void)sm;
    return fake_tx_fifo_full;
}

/** @brief Records one WS2812 word and advances fake time by one frame.
 * @param pio The unused fake PIO instance.
 * @param sm The unused fake state machine index.
 * @param data The WS2812 word to record.
 */
static inline void pio_sm_put(PIO pio, uint sm, uint32_t data) {
    (void)pio;
    (void)sm;
    if (fake_status_word_count < TEST_MAX_STATUS_WORDS) {
        fake_status_words[fake_status_word_count] = data;
        ++fake_status_word_count;
    }
    fake_now_us += TEST_WS2812_FRAME_US;
}

#endif
