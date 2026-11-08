/** @file rainbow.c
 * @brief Implements time-based rainbow colors without blocking delays.
 */

#include "nxs_rainbow.h"

/** @brief Duration of one hue step in milliseconds. */
#define NXS_HUE_STEP_MS 20u
/** @brief Number of color sectors in the rainbow. */
#define NXS_HUE_SECTOR_COUNT 6u
/** @brief Number of hue steps in one color sector. */
#define NXS_HUE_STEPS_PER_SECTOR 256u
/** @brief Total number of hue steps in one rainbow period. */
#define NXS_HUE_COUNT (NXS_HUE_SECTOR_COUNT * NXS_HUE_STEPS_PER_SECTOR)
/** @brief Maximum input value of one color channel. */
#define NXS_CHANNEL_MAX 255u
/** @brief Maximum output value of one dimmed color channel. */
#define NXS_STATUS_CHANNEL_MAX 16u
/** @brief Bit position of red in 0x00RRGGBB. */
#define NXS_RED_SHIFT 16u
/** @brief Bit position of green in 0x00RRGGBB. */
#define NXS_GREEN_SHIFT 8u
/** @brief Red-to-yellow color sector. */
#define NXS_SECTOR_RED_TO_YELLOW 0u
/** @brief Yellow-to-green color sector. */
#define NXS_SECTOR_YELLOW_TO_GREEN 1u
/** @brief Green-to-cyan color sector. */
#define NXS_SECTOR_GREEN_TO_CYAN 2u
/** @brief Cyan-to-blue color sector. */
#define NXS_SECTOR_CYAN_TO_BLUE 3u
/** @brief Blue-to-magenta color sector. */
#define NXS_SECTOR_BLUE_TO_MAGENTA 4u
/** @brief Magenta-to-red color sector. */
#define NXS_SECTOR_MAGENTA_TO_RED 5u
/** @brief Mask for red in 0x00RRGGBB. */
#define NXS_RED_MASK 0x00ff0000u
/** @brief Mask for green in 0x00RRGGBB. */
#define NXS_GREEN_MASK 0x0000ff00u
/** @brief Mask for blue in 0x00RRGGBB. */
#define NXS_BLUE_MASK 0x000000ffu
/** @brief Left shift that moves green from 0x00RRGGBB to 0xGGRRBB00. */
#define NXS_WS2812_GREEN_SHIFT 16u
/** @brief Left shift that moves blue from 0x00RRGGBB to 0xGGRRBB00. */
#define NXS_WS2812_BLUE_SHIFT 8u

/** @brief Scales a full-range channel to the status LED's brightness limit.
 * @param channel The full-range color channel.
 * @return The dimmed color channel.
 */
static uint32_t scale_channel(uint32_t channel) {
    return (channel * NXS_STATUS_CHANNEL_MAX) / NXS_CHANNEL_MAX;
}

/** @brief Calculates the dim rainbow color for an elapsed time. */
uint32_t nxs_rainbow_color(uint64_t elapsed_ms) {
    /** @brief Current position in the repeating hue range. */
    const uint32_t hue = (uint32_t)((elapsed_ms / NXS_HUE_STEP_MS) % (uint64_t)NXS_HUE_COUNT);
    /** @brief Current color sector. */
    const uint32_t sector = hue / NXS_HUE_STEPS_PER_SECTOR;
    /** @brief Rising channel value within the current sector. */
    const uint32_t offset = hue % NXS_HUE_STEPS_PER_SECTOR;
    /** @brief Falling channel value within the current sector. */
    const uint32_t falling = NXS_CHANNEL_MAX - offset;
    /** @brief Full-range red channel before brightness scaling. */
    uint32_t red = NXS_CHANNEL_MAX;
    /** @brief Full-range green channel before brightness scaling. */
    uint32_t green = 0;
    /** @brief Full-range blue channel before brightness scaling. */
    uint32_t blue = 0;
    switch (sector) {
    case NXS_SECTOR_RED_TO_YELLOW:
        green = offset;
        break;
    case NXS_SECTOR_YELLOW_TO_GREEN:
        red = falling;
        green = NXS_CHANNEL_MAX;
        break;
    case NXS_SECTOR_GREEN_TO_CYAN:
        red = 0;
        green = NXS_CHANNEL_MAX;
        blue = offset;
        break;
    case NXS_SECTOR_CYAN_TO_BLUE:
        red = 0;
        green = falling;
        blue = NXS_CHANNEL_MAX;
        break;
    case NXS_SECTOR_BLUE_TO_MAGENTA:
        red = offset;
        green = 0;
        blue = NXS_CHANNEL_MAX;
        break;
    case NXS_SECTOR_MAGENTA_TO_RED:
        blue = falling;
        break;
    default:
        break;
    }
    return (scale_channel(red) << NXS_RED_SHIFT) | (scale_channel(green) << NXS_GREEN_SHIFT) | scale_channel(blue);
}

/** @brief Converts an RGB color to the WS2812 byte order. */
uint32_t nxs_rainbow_ws2812_word(uint32_t color) {
    return ((color & NXS_GREEN_MASK) << NXS_WS2812_GREEN_SHIFT) | (color & NXS_RED_MASK) |
           ((color & NXS_BLUE_MASK) << NXS_WS2812_BLUE_SHIFT);
}
