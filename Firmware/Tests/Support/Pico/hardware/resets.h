#ifndef NXS_TEST_RESETS_H
#define NXS_TEST_RESETS_H
#include "hardware/regs/resets.h"
#include "pico.h"
static inline void reset_block(uint32_t mask) {
    (void)mask;
}
static inline void unreset_block_wait(uint32_t mask) {
    (void)mask;
}
#endif
