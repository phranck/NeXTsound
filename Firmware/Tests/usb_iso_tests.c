#include "device/dcd.h"
#include "hardware/structs/usb.h"
#include "nxs_test.h"
#include "pico.h"

#include <stdarg.h>
#include <string.h>

usb_hw_t nxs_test_usb_hw, nxs_test_usb_set, nxs_test_usb_clear;
_Alignas(4096) usb_device_dpram_t nxs_test_usb_dpram;

_Noreturn void panic(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);
    fputc('\n', stderr);
    exit(1);
}

void dcd_event_handler(const dcd_event_t *event, bool in_interrupt) {
    (void)event;
    (void)in_interrupt;
}

static tusb_desc_endpoint_t iso_descriptor(uint8_t endpoint, uint16_t bytes) {
    return (tusb_desc_endpoint_t){.bLength = sizeof(tusb_desc_endpoint_t),
                                  .bDescriptorType = TUSB_DESC_ENDPOINT,
                                  .bEndpointAddress = endpoint,
                                  .bmAttributes = {.xfer = TUSB_XFER_ISOCHRONOUS},
                                  .wMaxPacketSize = bytes,
                                  .bInterval = 1};
}

int main(void) {
    memset(&nxs_test_usb_hw, 0, sizeof(nxs_test_usb_hw));
    memset(&nxs_test_usb_set, 0, sizeof(nxs_test_usb_set));
    memset(&nxs_test_usb_clear, 0, sizeof(nxs_test_usb_clear));
    nxs_test_usb_hw.abort_done = UINT32_MAX; /* The logical fixture acknowledges aborts immediately. */
    tusb_rhport_init_t initialization = {.role = TUSB_ROLE_DEVICE, .speed = TUSB_SPEED_FULL};
    CHECK(dcd_init(0, &initialization));
    CHECK(dcd_edpt_iso_alloc(0, 0x01, 294));
    CHECK(dcd_edpt_iso_alloc(0, 0x81, 4));
    tusb_desc_endpoint_t hid = {.bLength = sizeof(tusb_desc_endpoint_t),
                                .bDescriptorType = TUSB_DESC_ENDPOINT,
                                .bEndpointAddress = 0x82,
                                .bmAttributes = {.xfer = TUSB_XFER_INTERRUPT},
                                .wMaxPacketSize = 16,
                                .bInterval = 1};
    CHECK(dcd_edpt_open(0, &hid));
    uint8_t bytes[294] = {0};
    CHECK(dcd_edpt_xfer(0, 0x82, bytes, 16));
    /* EP0 has no endpoint-control register. Preserve its logical buffer state without executing native EP0 MMIO. */
    usb_dpram->ep_buf_ctrl[0].in = USB_BUF_CTRL_AVAIL | 16u;
    uint32_t hid_pending = usb_dpram->ep_buf_ctrl[2].in;
    uint32_t control_pending = usb_dpram->ep_buf_ctrl[0].in;
    CHECK(hid_pending & USB_BUF_CTRL_AVAIL);
    CHECK(control_pending & USB_BUF_CTRL_AVAIL);
    for (unsigned int cycle = 0; cycle < 32; ++cycle) {
        uint16_t packet = cycle % 3 == 1 ? 294 : 196;
        tusb_desc_endpoint_t output = iso_descriptor(0x01, packet);
        CHECK(dcd_edpt_iso_activate(0, &output));
        CHECK((usb_dpram->ep_buf_ctrl[1].out & USB_BUF_CTRL_AVAIL) == 0);
        if (cycle != 0)
            CHECK(nxs_test_usb_set.abort == (1u << 3));
        CHECK(dcd_edpt_xfer(0, 0x01, bytes, packet));
        CHECK(usb_dpram->ep_buf_ctrl[1].out & USB_BUF_CTRL_AVAIL);
        CHECK((usb_dpram->ep_buf_ctrl[1].out & USB_BUF_CTRL_LEN_MASK) == packet);
        tusb_desc_endpoint_t feedback = iso_descriptor(0x81, 3);
        CHECK(dcd_edpt_iso_activate(0, &feedback));
        CHECK((usb_dpram->ep_buf_ctrl[1].in & USB_BUF_CTRL_AVAIL) == 0);
        if (cycle != 0)
            CHECK(nxs_test_usb_set.abort == (1u << 2));
        CHECK(dcd_edpt_xfer(0, 0x81, bytes, 3));
        CHECK(usb_dpram->ep_buf_ctrl[1].in & USB_BUF_CTRL_AVAIL);
        CHECK(usb_dpram->ep_buf_ctrl[2].in == hid_pending);
        CHECK(usb_dpram->ep_buf_ctrl[0].in == control_pending);
    }
    CHECK(dcd_deinit(0));
    return nxs_test_finish("RP2 ISO endpoint restart");
}
