#ifndef NXS_TEST_USB_STRUCTS_H
#define NXS_TEST_USB_STRUCTS_H
#include "hardware/regs/usb.h"
#include "hardware/structs/usb_dpram.h"
#include "pico.h"
/* Logical registers and separate alias-write records, not a controller or timing emulator. */
typedef struct {
    io_rw_32 dev_addr_ctrl, main_ctrl, buf_status, buf_cpu_should_handle, sie_status, sie_ctrl, inte, ints, pwr, muxing, abort, abort_done,
        ep_stall_arm, sof_rd;
} usb_hw_t;
extern usb_hw_t nxs_test_usb_hw, nxs_test_usb_set, nxs_test_usb_clear;
extern usb_device_dpram_t nxs_test_usb_dpram;
#define usb_hw (&nxs_test_usb_hw)
#undef usb_dpram
#define usb_dpram (&nxs_test_usb_dpram)
static inline void *hw_set_alias_untyped(const volatile void *pointer) {
    (void)pointer;
    return &nxs_test_usb_set;
}
static inline void *hw_clear_alias_untyped(const volatile void *pointer) {
    (void)pointer;
    return &nxs_test_usb_clear;
}
#endif
