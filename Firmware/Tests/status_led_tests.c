/** @file status_led_tests.c
 * @brief Tests the boot and ready colors of the onboard status LED.
 */

#include "nxs_status_led.h"
#include "nxs_test.h"

/** @brief Expected dim red in the WS2812's 0xGGRRBB00 format. */
#define TEST_BOOTING_WORD 0x00040000u
/** @brief Expected dim green in the WS2812's 0xGGRRBB00 format. */
#define TEST_READY_WORD 0x04000000u
/** @brief Name printed for this test suite. */
#define TEST_SUITE_NAME "Status LED"

/** @brief Verifies the exact boot and ready color words. */
static void status_colors_are_dim_red_and_green(void) {
    CHECK(NXS_STATUS_BOOTING_WORD == TEST_BOOTING_WORD);
    CHECK(NXS_STATUS_READY_WORD == TEST_READY_WORD);
}

/** @brief Runs the status LED checks.
 * @return EXIT_SUCCESS when every check passes.
 */
int main(void) {
    status_colors_are_dim_red_and_green();
    return nxs_test_finish(TEST_SUITE_NAME);
}
