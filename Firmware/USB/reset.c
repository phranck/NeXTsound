/*
 * Reset-interface driver adapted from Pico SDK 2.2.0 pico_stdio_usb/reset_interface.c.
 * Copyright (c) 2021 Raspberry Pi (Trading) Ltd.
 * SPDX-License-Identifier: BSD-3-Clause
 * The complete notice is retained in Firmware/ThirdParty/Pico-SDK-LICENSE.txt.
 */
#include "device/usbd_pvt.h"
#include "nxs_usb.h"
#include "pico/usb_reset_interface.h"
#include "tusb.h"

static bool interface_open;
static nxs_usb_reset_request_t pending;

static void reset_init(void) {
    interface_open = false;
    pending = (nxs_usb_reset_request_t){0};
}

static bool reset_deinit(void) {
    reset_init();
    return true;
}

static void reset_bus(uint8_t port) {
    (void)port;
    reset_init();
}

static uint16_t reset_open(uint8_t port, const tusb_desc_interface_t *descriptor, uint16_t maximum_length) {
    (void)port;
    if (!descriptor || maximum_length < sizeof(*descriptor) || descriptor->bLength != sizeof(*descriptor) ||
        descriptor->bInterfaceNumber != NXS_USB_RESET_INTERFACE || descriptor->bNumEndpoints != 0 ||
        descriptor->bInterfaceClass != TUSB_CLASS_VENDOR_SPECIFIC || descriptor->bInterfaceSubClass != RESET_INTERFACE_SUBCLASS ||
        descriptor->bInterfaceProtocol != RESET_INTERFACE_PROTOCOL) {
        return 0;
    }
    interface_open = true;
    return sizeof(*descriptor);
}

static bool request_valid(const tusb_control_request_t *request) {
    if (!interface_open || !request || request->bmRequestType != 0x21 || request->wIndex != NXS_USB_RESET_INTERFACE ||
        request->wLength != 0) {
        return false;
    }
    return (request->bRequest == RESET_REQUEST_BOOTSEL && request->wValue <= 1) ||
           (request->bRequest == RESET_REQUEST_FLASH && request->wValue == 0);
}

static bool reset_control(uint8_t port, uint8_t stage, const tusb_control_request_t *request) {
    if (!request_valid(request)) {
        return false;
    }
    if (stage == CONTROL_STAGE_SETUP) {
        return tud_control_status(port, request);
    }
    if (stage != CONTROL_STAGE_ACK) {
        return false;
    }
    pending.action = request->bRequest == RESET_REQUEST_BOOTSEL ? NXS_USB_RESET_BOOTSEL : NXS_USB_RESET_FLASH;
    pending.disable_mask = (uint8_t)request->wValue;
    return true;
}

static bool reset_transfer(uint8_t port, uint8_t endpoint, xfer_result_t result, uint32_t transferred) {
    (void)port;
    (void)endpoint;
    (void)result;
    (void)transferred;
    return false;
}

const usbd_class_driver_t *usbd_app_driver_get_cb(uint8_t *driver_count) {
    static const usbd_class_driver_t driver = {.name = "RESET",
                                               .init = reset_init,
                                               .deinit = reset_deinit,
                                               .reset = reset_bus,
                                               .open = reset_open,
                                               .control_xfer_cb = reset_control,
                                               .xfer_cb = reset_transfer};
    *driver_count = 1;
    return &driver;
}

nxs_usb_reset_request_t nxs_usb_pending_reset(void) {
    return pending;
}
