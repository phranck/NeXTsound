/*
 * Descriptor structure adapted from TinyUSB uac2_speaker_fb.
 * Copyright (c) 2023 HiFiPhile
 * SPDX-License-Identifier: MIT
 * The upstream notice is retained in Firmware/ThirdParty/TinyUSB-examples-LICENSE.txt.
 */
#include "nxs_usb.h"
#include "tusb.h"

#include <string.h>

static const char *device_serial;
static uint16_t string_buffer[64];

static const tusb_desc_device_t device_descriptor = {.bLength = sizeof(tusb_desc_device_t),
                                                     .bDescriptorType = TUSB_DESC_DEVICE,
                                                     .bcdUSB = 0x0200,
                                                     .bDeviceClass = TUSB_CLASS_MISC,
                                                     .bDeviceSubClass = MISC_SUBCLASS_COMMON,
                                                     .bDeviceProtocol = MISC_PROTOCOL_IAD,
                                                     .bMaxPacketSize0 = CFG_TUD_ENDPOINT0_SIZE,
                                                     .idVendor = NXS_USB_VENDOR_ID,
                                                     .idProduct = NXS_USB_PRODUCT_ID,
                                                     .bcdDevice = 0x0100,
                                                     .iManufacturer = 1,
                                                     .iProduct = 2,
                                                     .iSerialNumber = 3,
                                                     .bNumConfigurations = 1};

static const uint8_t hid_report[] = {HID_USAGE_PAGE_N(NXS_HID_USAGE_PAGE, 2),
                                     HID_USAGE(NXS_HID_USAGE),
                                     HID_COLLECTION(HID_COLLECTION_APPLICATION),
                                     HID_REPORT_ID(NXS_REPORT_ID) HID_USAGE(2),
                                     HID_LOGICAL_MIN(0),
                                     HID_LOGICAL_MAX_N(255, 2),
                                     HID_REPORT_SIZE(8),
                                     HID_REPORT_COUNT(NXS_REPORT_SIZE - 1u),
                                     HID_FEATURE(HID_DATA | HID_VARIABLE | HID_ABSOLUTE),
                                     HID_COLLECTION_END};

#define NXS_AUDIO_ALT_DESCRIPTOR(alternate, sample_bytes, resolution)                                                                      \
    TUD_AUDIO_DESC_STD_AS_INT(NXS_USB_AUDIO_STREAM_INTERFACE, alternate, 2, 0),                                                            \
        TUD_AUDIO_DESC_CS_AS_INT(NXS_USB_INPUT_ENTITY, AUDIO_CTRL_NONE, AUDIO_FORMAT_TYPE_I, AUDIO_DATA_FORMAT_TYPE_I_PCM,                 \
                                 NXS_AUDIO_CHANNELS, AUDIO_CHANNEL_CONFIG_NON_PREDEFINED, 0),                                              \
        TUD_AUDIO_DESC_TYPE_I_FORMAT(sample_bytes, resolution),                                                                            \
        TUD_AUDIO_DESC_STD_AS_ISO_EP(NXS_USB_AUDIO_OUT_ENDPOINT,                                                                           \
                                     TUSB_XFER_ISOCHRONOUS | TUSB_ISO_EP_ATT_ASYNCHRONOUS | TUSB_ISO_EP_ATT_DATA,                          \
                                     NXS_AUDIO_USB_MAX_FRAMES * NXS_AUDIO_CHANNELS * sample_bytes, 1),                                     \
        TUD_AUDIO_DESC_CS_AS_ISO_EP(AUDIO_CS_AS_ISO_DATA_EP_ATT_NON_MAX_PACKETS_OK, AUDIO_CTRL_NONE,                                       \
                                    AUDIO_CS_AS_ISO_DATA_EP_LOCK_DELAY_UNIT_MILLISEC, 1),                                                  \
        TUD_AUDIO_DESC_STD_AS_ISO_FB_EP(NXS_USB_FEEDBACK_ENDPOINT, 3, 1)

static const uint8_t configuration_descriptor[] = {
    TUD_CONFIG_DESCRIPTOR(1, NXS_USB_INTERFACE_COUNT, 0, NXS_USB_CONFIGURATION_LENGTH, 0, 500),
    TUD_AUDIO_DESC_IAD(NXS_USB_AUDIO_CONTROL_INTERFACE, 2, 0),
    TUD_AUDIO_DESC_STD_AC(NXS_USB_AUDIO_CONTROL_INTERFACE, 0, 4),
    TUD_AUDIO_DESC_CS_AC(0x0200, AUDIO_FUNC_DESKTOP_SPEAKER,
                         TUD_AUDIO_DESC_CLK_SRC_LEN + TUD_AUDIO_DESC_INPUT_TERM_LEN + TUD_AUDIO_DESC_OUTPUT_TERM_LEN +
                             TUD_AUDIO_DESC_FEATURE_UNIT_TWO_CHANNEL_LEN,
                         0),
    TUD_AUDIO_DESC_CLK_SRC(NXS_USB_CLOCK_ENTITY, AUDIO_CLOCK_SOURCE_ATT_INT_FIX_CLK,
                           (AUDIO_CTRL_R << AUDIO_CLOCK_SOURCE_CTRL_CLK_FRQ_POS) | (AUDIO_CTRL_R << AUDIO_CLOCK_SOURCE_CTRL_CLK_VAL_POS),
                           NXS_USB_INPUT_ENTITY, 0),
    TUD_AUDIO_DESC_INPUT_TERM(NXS_USB_INPUT_ENTITY, AUDIO_TERM_TYPE_USB_STREAMING, 0, NXS_USB_CLOCK_ENTITY, NXS_AUDIO_CHANNELS,
                              AUDIO_CHANNEL_CONFIG_NON_PREDEFINED, 0, 0, 0),
    TUD_AUDIO_DESC_OUTPUT_TERM(NXS_USB_OUTPUT_ENTITY, AUDIO_TERM_TYPE_OUT_DESKTOP_SPEAKER, 0, NXS_USB_FEATURE_ENTITY, NXS_USB_CLOCK_ENTITY,
                               0, 0),
    TUD_AUDIO_DESC_FEATURE_UNIT_TWO_CHANNEL(
        NXS_USB_FEATURE_ENTITY, NXS_USB_INPUT_ENTITY,
        (AUDIO_CTRL_RW << AUDIO_FEATURE_UNIT_CTRL_MUTE_POS) | (AUDIO_CTRL_RW << AUDIO_FEATURE_UNIT_CTRL_VOLUME_POS), 0, 0, 0),
    TUD_AUDIO_DESC_STD_AS_INT(NXS_USB_AUDIO_STREAM_INTERFACE, 0, 0, 0),
    NXS_AUDIO_ALT_DESCRIPTOR(1, 2, 16),
    NXS_AUDIO_ALT_DESCRIPTOR(2, 3, 24),
    TUD_HID_DESCRIPTOR(NXS_USB_HID_INTERFACE, 5, HID_ITF_PROTOCOL_NONE, sizeof(hid_report), NXS_USB_HID_ENDPOINT, 16, 16)};

_Static_assert(sizeof(configuration_descriptor) == NXS_USB_CONFIGURATION_LENGTH, "USB descriptor length mismatch");

void nxs_usb_set_serial(const char *serial) {
    device_serial = serial;
}

const uint8_t *tud_descriptor_device_cb(void) {
    return (const uint8_t *)&device_descriptor;
}

const uint8_t *tud_descriptor_configuration_cb(uint8_t index) {
    return index == 0 ? configuration_descriptor : NULL;
}

const uint8_t *tud_hid_descriptor_report_cb(uint8_t instance) {
    return instance == 0 ? hid_report : NULL;
}

const uint16_t *tud_descriptor_string_cb(uint8_t index, uint16_t language) {
    (void)language;
    if (index == 0) {
        string_buffer[0] = (TUSB_DESC_STRING << 8) | 4;
        string_buffer[1] = 0x0409;
        return string_buffer;
    }
    const char *strings[] = {NULL, "Layered", "NeXTsound development", device_serial, "NeXTsound Audio", "NeXTsound Control"};
    if (index >= sizeof(strings) / sizeof(strings[0]) || !strings[index]) {
        return NULL;
    }
    size_t length = strlen(strings[index]);
    if (length > sizeof(string_buffer) / sizeof(string_buffer[0]) - 1) {
        length = sizeof(string_buffer) / sizeof(string_buffer[0]) - 1;
    }
    for (size_t character = 0; character < length; ++character) {
        string_buffer[character + 1] = (uint8_t)strings[index][character];
    }
    string_buffer[0] = (uint16_t)((TUSB_DESC_STRING << 8) | (2u * length + 2u));
    return string_buffer;
}
