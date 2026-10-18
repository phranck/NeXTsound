#include "device/usbd_pvt.h"
#include "nxs_test.h"
#include "nxs_usb.h"
#include "pico/usb_reset_interface.h"
#include "tusb.h"

static unsigned int status_transfers;

bool tud_control_status(uint8_t port, const tusb_control_request_t *request) {
    CHECK(port == 0 && request != NULL);
    ++status_transfers;
    return true;
}

static tusb_desc_interface_t descriptor(void) {
    return (tusb_desc_interface_t){.bLength = sizeof(tusb_desc_interface_t),
                                   .bDescriptorType = TUSB_DESC_INTERFACE,
                                   .bInterfaceNumber = NXS_USB_RESET_INTERFACE,
                                   .bNumEndpoints = 0,
                                   .bInterfaceClass = TUSB_CLASS_VENDOR_SPECIFIC,
                                   .bInterfaceSubClass = RESET_INTERFACE_SUBCLASS,
                                   .bInterfaceProtocol = RESET_INTERFACE_PROTOCOL};
}

int main(void) {
    uint8_t count;
    const usbd_class_driver_t *driver = usbd_app_driver_get_cb(&count);
    CHECK(driver != NULL && count == 1);
    driver->init();
    CHECK(nxs_usb_pending_reset().action == NXS_USB_RESET_NONE);
    tusb_desc_interface_t interface = descriptor();
    CHECK(driver->open(0, NULL, sizeof(interface)) == 0);
    CHECK(driver->open(0, &interface, sizeof(interface) - 1u) == 0);
    for (unsigned int invalid = 0; invalid < 4; ++invalid) {
        tusb_desc_interface_t wrong = interface;
        switch (invalid) {
        case 0:
            wrong.bInterfaceNumber = NXS_USB_HID_INTERFACE;
            break;
        case 1:
            wrong.bInterfaceClass = TUSB_CLASS_HID;
            break;
        case 2:
            wrong.bInterfaceProtocol = 0;
            break;
        case 3:
            wrong.bNumEndpoints = 1;
            break;
        }
        CHECK(driver->open(0, &wrong, sizeof(wrong)) == 0);
    }
    CHECK(driver->open(0, &interface, sizeof(interface)) == sizeof(interface));
    tusb_control_request_t request = {.bmRequestType = 0x21, .bRequest = RESET_REQUEST_BOOTSEL, .wIndex = NXS_USB_RESET_INTERFACE};
    CHECK(driver->control_xfer_cb(0, CONTROL_STAGE_SETUP, &request));
    CHECK(status_transfers == 1 && nxs_usb_pending_reset().action == NXS_USB_RESET_NONE);
    CHECK(driver->control_xfer_cb(0, CONTROL_STAGE_ACK, &request));
    CHECK(nxs_usb_pending_reset().action == NXS_USB_RESET_BOOTSEL && nxs_usb_pending_reset().disable_mask == 0);
    request.wValue = 1;
    CHECK(driver->control_xfer_cb(0, CONTROL_STAGE_SETUP, &request));
    CHECK(driver->control_xfer_cb(0, CONTROL_STAGE_ACK, &request));
    CHECK(nxs_usb_pending_reset().action == NXS_USB_RESET_BOOTSEL && nxs_usb_pending_reset().disable_mask == 1);
    request.bRequest = RESET_REQUEST_FLASH;
    request.wValue = 0;
    CHECK(driver->control_xfer_cb(0, CONTROL_STAGE_SETUP, &request));
    CHECK(driver->control_xfer_cb(0, CONTROL_STAGE_ACK, &request));
    CHECK(nxs_usb_pending_reset().action == NXS_USB_RESET_FLASH);
    for (unsigned int invalid = 0; invalid < 6; ++invalid) {
        tusb_control_request_t wrong = request;
        switch (invalid) {
        case 0:
            wrong.bmRequestType = 0x41;
            break;
        case 1:
            wrong.wIndex = NXS_USB_HID_INTERFACE;
            break;
        case 2:
            wrong.wLength = 1;
            break;
        case 3:
            wrong.bRequest = 0xff;
            break;
        case 4:
            wrong.wValue = 1;
            break;
        case 5:
            wrong.bRequest = RESET_REQUEST_BOOTSEL;
            wrong.wValue = 2;
            break;
        }
        CHECK(!driver->control_xfer_cb(0, CONTROL_STAGE_SETUP, &wrong));
        CHECK(!driver->control_xfer_cb(0, CONTROL_STAGE_ACK, &wrong));
        CHECK(nxs_usb_pending_reset().action == NXS_USB_RESET_FLASH);
    }
    CHECK(!driver->control_xfer_cb(0, CONTROL_STAGE_SETUP, NULL));
    CHECK(!driver->control_xfer_cb(0, CONTROL_STAGE_DATA, &request));
    CHECK(!driver->xfer_cb(0, 0, XFER_RESULT_SUCCESS, 0));
    driver->reset(0);
    CHECK(nxs_usb_pending_reset().action == NXS_USB_RESET_NONE);
    CHECK(!driver->control_xfer_cb(0, CONTROL_STAGE_ACK, &request));
    CHECK(driver->open(0, &interface, sizeof(interface)) == sizeof(interface));
    CHECK(driver->control_xfer_cb(0, CONTROL_STAGE_SETUP, &request));
    CHECK(driver->control_xfer_cb(0, CONTROL_STAGE_ACK, &request));
    CHECK(driver->deinit());
    CHECK(nxs_usb_pending_reset().action == NXS_USB_RESET_NONE);
    return nxs_test_finish("USB maintenance reset");
}
