#ifndef NXS_TEST_PICO_H
#define NXS_TEST_PICO_H
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef unsigned int uint;
#ifndef __unused
#define __unused __attribute__((unused))
#endif
#define _u(value) value##u
#define hard_assert(value) assert(value)
_Noreturn void panic(const char *format, ...);
static inline unsigned int rp2040_chip_version(void) {
    return 2;
}
static inline void busy_wait_at_least_cycles(uint32_t cycles) {
    (void)cycles;
}
#define remove_volatile_cast(type, pointer) ((type)(pointer))
#endif
