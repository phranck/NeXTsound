/** @file time.h
 * @brief Host fixture for the time calls used by the status LED driver.
 */

/** @brief Include guard for the fake time interface. */
#ifndef TEST_PICO_TIME_H
#define TEST_PICO_TIME_H

#include <stdbool.h>
#include <stdint.h>

/** @brief Fake absolute timestamp in microseconds. */
typedef uint64_t absolute_time_t;

/** @brief Current fake timestamp in microseconds. */
extern uint64_t fake_now_us;

/** @brief Reads the current fake timestamp.
 * @return The value of fake_now_us.
 */
static inline absolute_time_t get_absolute_time(void) {
    return fake_now_us;
}

/** @brief Creates a fake timeout relative to the current fake timestamp.
 * @param milliseconds Delay in milliseconds.
 * @return The fake timestamp after the requested delay.
 */
static inline absolute_time_t make_timeout_time_ms(uint32_t milliseconds) {
    return fake_now_us + ((uint64_t)milliseconds * 1000u);
}

/** @brief Checks whether fake time has reached a target.
 * @param target The target fake timestamp.
 * @return True when fake_now_us is at or after target.
 */
static inline bool time_reached(absolute_time_t target) {
    return fake_now_us >= target;
}

#endif
