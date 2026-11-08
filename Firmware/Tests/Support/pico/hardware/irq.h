#ifndef NXS_TEST_IRQ_H
#define NXS_TEST_IRQ_H
#include "pico.h"
#define USBCTRL_IRQ 0u
typedef void (*irq_handler_t)(void);
static inline void irq_add_shared_handler(uint number, irq_handler_t handler, uint8_t priority) {
    (void)number;
    (void)handler;
    (void)priority;
}
static inline void irq_remove_handler(uint number, irq_handler_t handler) {
    (void)number;
    (void)handler;
}
static inline void irq_set_enabled(uint number, bool enabled) {
    (void)number;
    (void)enabled;
}
#endif
