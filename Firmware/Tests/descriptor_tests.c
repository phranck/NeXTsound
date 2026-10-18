#include "nxs_test.h"
#include "nxs_usb.h"
#include "pico/usb_reset_interface.h"
#include "tusb.h"

static uint16_t read_u16(const uint8_t *bytes) {
    return (uint16_t)(bytes[0] | ((uint16_t)bytes[1] << 8));
}

int main(void) {
    const tusb_desc_device_t *device = (const tusb_desc_device_t *)tud_descriptor_device_cb();
    CHECK(device->idVendor == NXS_USB_VENDOR_ID && device->idProduct == NXS_USB_PRODUCT_ID);
    CHECK(device->bDeviceClass == TUSB_CLASS_MISC && device->bNumConfigurations == 1);
    const uint8_t *configuration = tud_descriptor_configuration_cb(0);
    CHECK(configuration != NULL && tud_descriptor_configuration_cb(1) == NULL);
    size_t length = read_u16(configuration + 2);
    CHECK(length == NXS_USB_CONFIGURATION_LENGTH && configuration[4] == NXS_USB_INTERFACE_COUNT);
    uint8_t interface = 0xff, alternate = 0;
    unsigned int formats = 0, feedback_endpoints = 0, hid_interfaces = 0, reset_interfaces = 0;
    size_t hid_length = 0;
    for (size_t offset = 0; offset < length;) {
        const uint8_t *descriptor = configuration + offset;
        CHECK(descriptor[0] >= 2 && offset + descriptor[0] <= length);
        if (descriptor[1] == TUSB_DESC_INTERFACE) {
            interface = descriptor[2];
            alternate = descriptor[3];
            if (descriptor[5] == TUSB_CLASS_HID) {
                ++hid_interfaces;
                CHECK(interface == NXS_USB_HID_INTERFACE && descriptor[4] == 1);
            } else if (descriptor[5] == TUSB_CLASS_VENDOR_SPECIFIC) {
                ++reset_interfaces;
                CHECK(interface == NXS_USB_RESET_INTERFACE && descriptor[3] == 0 && descriptor[4] == 0);
                CHECK(descriptor[6] == RESET_INTERFACE_SUBCLASS && descriptor[7] == RESET_INTERFACE_PROTOCOL);
            }
        } else if (descriptor[1] == TUSB_DESC_CS_INTERFACE && interface == NXS_USB_AUDIO_STREAM_INTERFACE &&
                   descriptor[2] == AUDIO_CS_AS_INTERFACE_FORMAT_TYPE) {
            CHECK(alternate == 1 || alternate == 2);
            CHECK(descriptor[4] == alternate + 1 && descriptor[5] == (alternate == 1 ? 16 : 24));
            ++formats;
        } else if (descriptor[1] == TUSB_DESC_ENDPOINT) {
            uint16_t packet = read_u16(descriptor + 4);
            if (descriptor[2] == NXS_USB_FEEDBACK_ENDPOINT) {
                CHECK(packet == 3 && descriptor[6] == 1);
                ++feedback_endpoints;
            } else if (descriptor[2] == NXS_USB_AUDIO_OUT_ENDPOINT) {
                CHECK(packet == NXS_AUDIO_USB_MAX_FRAMES * NXS_AUDIO_CHANNELS * (alternate + 1u));
                CHECK((descriptor[3] & 0x0fu) == (TUSB_XFER_ISOCHRONOUS | TUSB_ISO_EP_ATT_ASYNCHRONOUS));
            } else {
                CHECK(descriptor[2] == NXS_USB_HID_ENDPOINT && packet <= 64);
            }
        } else if (descriptor[1] == HID_DESC_TYPE_HID && interface == NXS_USB_HID_INTERFACE) {
            hid_length = read_u16(descriptor + 7);
        }
        offset += descriptor[0];
    }
    CHECK(formats == 2 && feedback_endpoints == 2 && hid_interfaces == 1 && reset_interfaces == 1 && hid_length != 0);
    const uint8_t *report = tud_hid_descriptor_report_cb(0);
    uint32_t count = 0, size = 0, report_id = 0, page = 0, feature_bits = 0;
    for (size_t offset = 0; offset < hid_length;) {
        uint8_t prefix = report[offset++];
        unsigned int bytes = prefix & 3u;
        if (bytes == 3) {
            bytes = 4;
        }
        CHECK(offset + bytes <= hid_length);
        uint32_t value = 0;
        for (unsigned int byte = 0; byte < bytes; ++byte) {
            value |= (uint32_t)report[offset++] << (byte * 8);
        }
        switch (prefix & 0xfcu) {
        case 0x04:
            page = value;
            break;
        case 0x74:
            size = value;
            break;
        case 0x84:
            report_id = value;
            break;
        case 0x94:
            count = value;
            break;
        case 0xb0:
            feature_bits += count * size;
            break;
        default:
            break;
        }
    }
    CHECK(page == NXS_HID_USAGE_PAGE && report_id == NXS_REPORT_ID);
    CHECK(feature_bits == (NXS_REPORT_SIZE - 1u) * 8u);
    nxs_usb_set_serial("TESTDEVICE");
    const uint16_t *serial = tud_descriptor_string_cb(3, 0x0409);
    CHECK(serial != NULL && (serial[0] & 0xffu) == 22);
    CHECK(tud_descriptor_string_cb(255, 0x0409) == NULL);
    return nxs_test_finish("USB descriptor");
}
