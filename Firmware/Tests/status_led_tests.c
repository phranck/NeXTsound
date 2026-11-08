/** @file status_led_tests.c
 * @brief Tests the boot and ready colors and timing of the onboard status LED.
 */

#include "nxs_status_led.h"
#include "nxs_test.h"

#include "hardware/pio.h"
#include "pico/time.h"

/** @brief Expected dim red in the WS2812's 0xGGRRBB00 format. */
#define TEST_BOOTING_WORD 0x00040000u
/** @brief Expected dim green in the WS2812's 0xGGRRBB00 format. */
#define TEST_READY_WORD 0x04000000u
/** @brief Timestamp at which the fake red frame has just been written. */
#define TEST_RED_WRITTEN_US 30u
/** @brief Timestamp after the red frame but before its 1 ms delay expires. */
#define TEST_BEFORE_READY_US 1000u
/** @brief Timestamp at which the 1 ms delay after the red frame expires. */
#define TEST_READY_US 1030u
/** @brief Name printed for this test suite. */
#define TEST_SUITE_NAME "Status LED"

/** @brief Whether the fake PIO FIFO is full. */
bool fake_tx_fifo_full = false;
/** @brief WS2812 words written through the fake PIO. */
uint32_t fake_status_words[TEST_MAX_STATUS_WORDS] = {0};
/** @brief Number of WS2812 words written through the fake PIO. */
unsigned int fake_status_word_count = 0;
/** @brief Current fake timestamp in microseconds. */
uint64_t fake_now_us = 0;

/** @brief Verifies the exact boot and ready color words. */
static void status_colors_are_dim_red_and_green(void) {
    CHECK(NXS_STATUS_BOOTING_WORD == TEST_BOOTING_WORD);
    CHECK(NXS_STATUS_READY_WORD == TEST_READY_WORD);
}

/** @brief Resets the fake time, FIFO, and recorded LED output. */
static void reset_fixture(void) {
    fake_tx_fifo_full = false;
    fake_status_word_count = 0;
    fake_now_us = 0;
    /** @brief Index of the recorded word being reset. */
    unsigned int index = 0;
    for (; index < TEST_MAX_STATUS_WORDS; ++index) {
        fake_status_words[index] = 0;
    }
}

/** @brief Verifies that green waits for the latch interval and for room in the PIO FIFO. */
static void ready_waits_for_latch_and_fifo(void) {
    reset_fixture();
    CHECK(nxs_status_led_init());
    CHECK(fake_status_word_count == 1u);
    CHECK(fake_status_words[0] == TEST_BOOTING_WORD);
    CHECK(fake_now_us == TEST_RED_WRITTEN_US);
    fake_now_us = TEST_BEFORE_READY_US;
    CHECK(!nxs_status_led_ready());
    CHECK(fake_status_word_count == 1u);
    fake_now_us = TEST_READY_US;
    fake_tx_fifo_full = true;
    CHECK(!nxs_status_led_ready());
    CHECK(fake_status_word_count == 1u);
    fake_tx_fifo_full = false;
    CHECK(nxs_status_led_ready());
    CHECK(fake_status_word_count == 2u);
    CHECK(fake_status_words[1] == TEST_READY_WORD);
}

/** @brief Runs the status LED checks.
 * @return EXIT_SUCCESS when every check passes.
 */
int main(void) {
    status_colors_are_dim_red_and_green();
    ready_waits_for_latch_and_fifo();
    return nxs_test_finish(TEST_SUITE_NAME);
}
