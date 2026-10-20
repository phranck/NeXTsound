#include "device/usbd_pvt.h"
#include "nxs_test.h"
#include "nxs_usb.h"
#include "tusb.h"

#include <string.h>

/* TinyUSB's own audio class driver runs here against stubs of the usbd core, so the bytes it hands
 * to the feedback endpoint are read where the RP2350 driver would take them. macOS reads full-speed
 * feedback as 10.14 in exactly three bytes and rejects every other size (issue 43); the pinned
 * TinyUSB only does that with the feedback patch from Firmware/ThirdParty applied. */

static struct {
    tusb_speed_t speed;
    unsigned int feedback_transfers;
    unsigned int out_transfers;
    uint16_t feedback_length;
    uint8_t feedback_bytes[4];
    uint8_t control_buffer[CFG_TUD_AUDIO_CTRL_BUF_SZ];
} host;

tusb_speed_t tud_speed_get(void) {
    return host.speed;
}

uint8_t *usbd_get_ctrl_buf(void) {
    return host.control_buffer;
}

bool usbd_edpt_open(uint8_t rhport, const tusb_desc_endpoint_t *descriptor) {
    CHECK(rhport == 0 && descriptor != NULL);
    return true;
}

/* The host build takes the same allocate-then-activate path for isochronous endpoints as the RP2350 driver. */
bool usbd_edpt_iso_alloc(uint8_t rhport, uint8_t endpoint, uint16_t largest_packet_size) {
    CHECK(rhport == 0 && largest_packet_size != 0);
    CHECK(endpoint == NXS_USB_AUDIO_OUT_ENDPOINT || endpoint == NXS_USB_FEEDBACK_ENDPOINT);
    return true;
}

bool usbd_edpt_iso_activate(uint8_t rhport, const tusb_desc_endpoint_t *descriptor) {
    CHECK(rhport == 0 && descriptor != NULL);
    return true;
}

void usbd_edpt_close(uint8_t rhport, uint8_t endpoint) {
    (void)rhport;
    (void)endpoint;
}

void usbd_edpt_clear_stall(uint8_t rhport, uint8_t endpoint) {
    (void)rhport;
    (void)endpoint;
}

void usbd_sof_enable(uint8_t rhport, sof_consumer_t consumer, bool enable) {
    (void)rhport;
    (void)consumer;
    (void)enable;
}

bool tud_control_xfer(uint8_t rhport, const tusb_control_request_t *request, void *buffer, uint16_t length) {
    (void)rhport;
    (void)request;
    (void)buffer;
    (void)length;
    return true;
}

bool tud_control_status(uint8_t rhport, const tusb_control_request_t *request) {
    (void)rhport;
    (void)request;
    return true;
}

bool usbd_edpt_xfer(uint8_t rhport, uint8_t endpoint, uint8_t *buffer, uint16_t total_bytes, bool in_isr) {
    (void)in_isr;
    CHECK(rhport == 0 && buffer != NULL);
    if (endpoint == NXS_USB_FEEDBACK_ENDPOINT) {
        CHECK(total_bytes <= sizeof(host.feedback_bytes));
        memcpy(host.feedback_bytes, buffer, total_bytes);
        host.feedback_length = total_bytes;
        ++host.feedback_transfers;
    } else {
        CHECK(endpoint == NXS_USB_AUDIO_OUT_ENDPOINT);
        ++host.out_transfers;
    }
    return true;
}

static void set_alternate(uint8_t alternate) {
    tusb_control_request_t request = {
        .bmRequestType = 0x01, .bRequest = TUSB_REQ_SET_INTERFACE, .wIndex = NXS_USB_AUDIO_STREAM_INTERFACE, .wValue = alternate};
    CHECK(audiod_control_xfer_cb(0, CONTROL_STAGE_SETUP, &request));
}

/* The driver sends the next packet from inside the completion of the previous one. */
static void complete_feedback(uint32_t feedback) {
    CHECK(tud_audio_n_fb_set(0, feedback));
    CHECK(audiod_xfer_isr(0, NXS_USB_FEEDBACK_ENDPOINT, XFER_RESULT_SUCCESS, host.feedback_length));
}

static void check_feedback_bytes(uint16_t length, uint8_t first, uint8_t second, uint8_t third) {
    CHECK(host.feedback_length == length);
    CHECK(host.feedback_bytes[0] == first && host.feedback_bytes[1] == second && host.feedback_bytes[2] == third);
}

int main(void) {
    memset(&host, 0, sizeof(host));
    host.speed = TUSB_SPEED_FULL;
    audiod_init();
    const uint8_t *configuration = tud_descriptor_configuration_cb(0);
    uint16_t total_length = (uint16_t)(configuration[2] | ((uint16_t)configuration[3] << 8));
    const size_t control_offset = TUD_CONFIG_DESC_LEN + TUD_AUDIO20_DESC_IAD_LEN;
    const tusb_desc_interface_t *control = (const tusb_desc_interface_t *)(configuration + control_offset);
    CHECK(audiod_open(0, control, (uint16_t)(total_length - control_offset)) == NXS_USB_AUDIO_DESCRIPTOR_LENGTH - TUD_AUDIO20_DESC_IAD_LEN);

    set_alternate(1);
    /* The driver arms the OUT endpoint and sends a first feedback packet before the firmware sets a value. */
    CHECK(host.out_transfers == 1 && host.feedback_transfers == 1);
    check_feedback_bytes(3, 0x00, 0x00, 0x00);

    /* 48.0 frames per millisecond in 16.16 is 0x00300000; in 10.14 it is 0x0c0000. */
    complete_feedback(48u << 16);
    CHECK(host.feedback_transfers == 2);
    check_feedback_bytes(3, 0x00, 0x00, 0x0c);

    /* 48.1875 frames per millisecond exercises the fraction bits and the two-bit shift. */
    complete_feedback((48u << 16) + 12288u);
    check_feedback_bytes(3, 0x00, 0x0c, 0x0c);

    /* High speed keeps the 16.16 four-byte format the specification assigns to it. */
    host.speed = TUSB_SPEED_HIGH;
    complete_feedback(48u << 16);
    check_feedback_bytes(4, 0x00, 0x00, 0x30);
    CHECK(host.feedback_bytes[3] == 0x00);

    set_alternate(0);
    return nxs_test_finish("USB feedback packet format");
}
