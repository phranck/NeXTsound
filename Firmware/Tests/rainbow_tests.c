/** @file rainbow_tests.c
 * @brief Tests the onboard status LED's rainbow color sequence.
 */

#include "nxs_rainbow.h"
#include "nxs_test.h"

// These expected values are an independent behavioral oracle for the constants in rainbow.c.
/** @brief Bit position of red in 0x00RRGGBB. */
#define RED_CHANNEL_SHIFT 16u
/** @brief Bit position of green in 0x00RRGGBB. */
#define GREEN_CHANNEL_SHIFT 8u
/** @brief Bit position of blue in 0x00RRGGBB. */
#define BLUE_CHANNEL_SHIFT 0u
/** @brief Mask for one extracted color channel. */
#define COLOR_CHANNEL_MASK 0xffu
/** @brief Maximum permitted output value per color channel. */
#define TEST_MAX_CHANNEL 4u
/** @brief Expected duration of one hue step. */
#define TEST_HUE_STEP_MS 20u
/** @brief Expected number of hue steps in one period. */
#define TEST_HUE_COUNT 1536u
/** @brief Expected duration of one complete rainbow period. */
#define TEST_PERIOD_MS 30720u
/** @brief First timestamp beyond the old 32-bit millisecond range. */
#define TEST_BEYOND_U32_TIME_MS UINT64_C(4294967296)
/** @brief Expected start time of yellow. */
#define TEST_YELLOW_MS 5120u
/** @brief Expected start time of green. */
#define TEST_GREEN_MS 10240u
/** @brief Expected start time of cyan. */
#define TEST_CYAN_MS 15360u
/** @brief Expected start time of blue. */
#define TEST_BLUE_MS 20480u
/** @brief Expected start time of magenta. */
#define TEST_MAGENTA_MS 25600u
/** @brief Expected dim red. */
#define TEST_DIM_RED 0x00040000u
/** @brief Expected dim yellow. */
#define TEST_DIM_YELLOW 0x00040400u
/** @brief Expected dim green. */
#define TEST_DIM_GREEN 0x00000400u
/** @brief Expected dim cyan. */
#define TEST_DIM_CYAN 0x00000404u
/** @brief Expected dim blue. */
#define TEST_DIM_BLUE 0x00000004u
/** @brief Expected dim magenta. */
#define TEST_DIM_MAGENTA 0x00040004u
/** @brief Expected color at 2^32 milliseconds, where hue 204 gives red 4 and green 3. */
#define TEST_DIM_AT_U32_WRAP 0x00040300u
/** @brief RGB sample with three distinct color channels. */
#define TEST_RGB_SAMPLE 0x00102030u
/** @brief WS2812 word for TEST_RGB_SAMPLE. */
#define TEST_WS2812_SAMPLE 0x20103000u
/** @brief Name printed for this test suite. */
#define TEST_SUITE_NAME "Rainbow"

/** @brief Extracts one eight-bit color channel.
 * @param color The RGB color in 0x00RRGGBB format.
 * @param shift The channel's right-shift count.
 * @return The extracted color channel.
 */
static uint32_t color_channel(uint32_t color, unsigned int shift) {
    return (color >> shift) & COLOR_CHANNEL_MASK;
}

/** @brief Verifies all six color sectors and the brightness limit across the complete hue range. */
static void rainbow_covers_full_hue_range_at_low_brightness(void) {
    CHECK(nxs_rainbow_color(0u) == TEST_DIM_RED);
    CHECK(nxs_rainbow_color(TEST_YELLOW_MS) == TEST_DIM_YELLOW);
    CHECK(nxs_rainbow_color(TEST_GREEN_MS) == TEST_DIM_GREEN);
    CHECK(nxs_rainbow_color(TEST_CYAN_MS) == TEST_DIM_CYAN);
    CHECK(nxs_rainbow_color(TEST_BLUE_MS) == TEST_DIM_BLUE);
    CHECK(nxs_rainbow_color(TEST_MAGENTA_MS) == TEST_DIM_MAGENTA);
    /** @brief Current hue position under test. */
    uint32_t hue = 0;
    for (; hue < TEST_HUE_COUNT; ++hue) {
        /** @brief Color produced at the current hue position. */
        const uint32_t color = nxs_rainbow_color(hue * TEST_HUE_STEP_MS);
        /** @brief Dimmed red channel under test. */
        const uint32_t red = color_channel(color, RED_CHANNEL_SHIFT);
        /** @brief Dimmed green channel under test. */
        const uint32_t green = color_channel(color, GREEN_CHANNEL_SHIFT);
        /** @brief Dimmed blue channel under test. */
        const uint32_t blue = color_channel(color, BLUE_CHANNEL_SHIFT);
        CHECK(red <= TEST_MAX_CHANNEL);
        CHECK(green <= TEST_MAX_CHANNEL);
        CHECK(blue <= TEST_MAX_CHANNEL);
        CHECK(red == TEST_MAX_CHANNEL || green == TEST_MAX_CHANNEL || blue == TEST_MAX_CHANNEL);
    }
}

/** @brief Verifies that complete periods restart at the same colors. */
static void rainbow_repeats_after_full_period(void) {
    CHECK(nxs_rainbow_color(TEST_PERIOD_MS) == TEST_DIM_RED);
    CHECK(nxs_rainbow_color(TEST_PERIOD_MS + TEST_YELLOW_MS) == TEST_DIM_YELLOW);
    CHECK(nxs_rainbow_color(TEST_PERIOD_MS + TEST_GREEN_MS) == TEST_DIM_GREEN);
    CHECK(nxs_rainbow_color(TEST_BEYOND_U32_TIME_MS) == TEST_DIM_AT_U32_WRAP);
}

/** @brief Verifies the green, red, blue byte order required by the WS2812 program. */
static void ws2812_word_orders_color_channels(void) {
    CHECK(nxs_rainbow_ws2812_word(TEST_RGB_SAMPLE) == TEST_WS2812_SAMPLE);
}

/** @brief Runs the rainbow behavior checks.
 * @return EXIT_SUCCESS when every check passes.
 */
int main(void) {
    rainbow_covers_full_hue_range_at_low_brightness();
    rainbow_repeats_after_full_period();
    ws2812_word_orders_color_channels();
    return nxs_test_finish(TEST_SUITE_NAME);
}
