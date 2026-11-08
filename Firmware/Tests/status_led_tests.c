/** @file status_led_tests.c
 * @brief Tests the boot and ready colors of the onboard status LED.
 */

#include "nxs_status_led.h"
#include "nxs_test.h"

#include "hardware/pio.h"

/** @brief Expected dim red in the WS2812's 0xGGRRBB00 format. */
#define TEST_BOOTING_WORD 0x04000000u
/** @brief Expected dim green in the WS2812's 0xGGRRBB00 format. */
#define TEST_READY_WORD 0x00040000u
/** @brief Name printed for this test suite. */
#define TEST_SUITE_NAME "Status LED"

/** @brief Whether the fake PIO FIFO is full. */
bool fake_tx_fifo_full = false;
/** @brief WS2812 words written through the fake PIO. */
uint32_t fake_status_words[TEST_MAX_STATUS_WORDS] = {0};
/** @brief Number of WS2812 words written through the fake PIO. */
unsigned int fake_status_word_count = 0;
/** @brief Number of times the fake state machine was disabled. */
unsigned int fake_disable_count = 0;
/** @brief Number of times the fake FIFO was cleared. */
unsigned int fake_fifo_clear_count = 0;
/** @brief Number of times the fake WS2812 program was initialized. */
unsigned int fake_program_init_count = 0;

/** @brief Verifies the exact boot and ready color words. */
static void status_colors_are_dim_red_and_green(void) {
    CHECK(NXS_STATUS_BOOTING_WORD == TEST_BOOTING_WORD);
    CHECK(NXS_STATUS_READY_WORD == TEST_READY_WORD);
}

/** @brief Resets the fake FIFO and recorded LED output. */
static void reset_fixture(void) {
    fake_tx_fifo_full = false;
    fake_status_word_count = 0;
    fake_disable_count = 0;
    fake_fifo_clear_count = 0;
    fake_program_init_count = 0;
    /** @brief Index of the recorded word being reset. */
    unsigned int index = 0;
    for (; index < TEST_MAX_STATUS_WORDS; ++index) {
        fake_status_words[index] = 0;
    }
}

/** @brief Verifies that initialization writes red and the ready call writes green. */
static void initialization_writes_red_then_ready_writes_green(void) {
    reset_fixture();
    CHECK(nxs_status_led_init());
    CHECK(fake_status_word_count == 1u);
    CHECK(fake_status_words[0] == TEST_BOOTING_WORD);
    CHECK(fake_disable_count == 0u);
    CHECK(fake_fifo_clear_count == 0u);
    CHECK(fake_program_init_count == 1u);
    CHECK(nxs_status_led_ready());
    CHECK(fake_disable_count == 1u);
    CHECK(fake_fifo_clear_count == 1u);
    CHECK(fake_program_init_count == 2u);
    CHECK(fake_status_word_count == 2u);
    CHECK(fake_status_words[1] == TEST_READY_WORD);
}

/** @brief Runs the status LED checks.
 * @return EXIT_SUCCESS when every check passes.
 */
int main(void) {
    status_colors_are_dim_red_and_green();
    initialization_writes_red_then_ready_writes_green();
    return nxs_test_finish(TEST_SUITE_NAME);
}
