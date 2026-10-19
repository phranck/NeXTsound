#ifndef NXS_USB_H
#define NXS_USB_H

#include "nxs_audio.h"
#include "nxs_storage.h"

#define NXS_USB_AUDIO_CONTROL_INTERFACE 0u
#define NXS_USB_AUDIO_STREAM_INTERFACE 1u
/* NXS_USB_HID_INTERFACE is defined in the shared nxs_protocol.h; the Mac app reads the same constant. */
#define NXS_USB_RESET_INTERFACE 3u
#define NXS_USB_INTERFACE_COUNT 4u
#define NXS_USB_RESET_DESCRIPTOR_LENGTH 9u
#define NXS_USB_CLOCK_ENTITY 4u
#define NXS_USB_INPUT_ENTITY 1u
#define NXS_USB_FEATURE_ENTITY 2u
#define NXS_USB_OUTPUT_ENTITY 3u
#define NXS_USB_AUDIO_OUT_ENDPOINT 0x01u
#define NXS_USB_FEEDBACK_ENDPOINT 0x81u
#define NXS_USB_HID_ENDPOINT 0x82u
#define NXS_USB_MAX_AUDIO_PACKET (NXS_AUDIO_USB_MAX_FRAMES * NXS_AUDIO_CHANNELS * 3u)

#define NXS_USB_STREAM_ALT_LENGTH                                                                                                          \
    (TUD_AUDIO_DESC_STD_AS_INT_LEN + TUD_AUDIO_DESC_CS_AS_INT_LEN + TUD_AUDIO_DESC_TYPE_I_FORMAT_LEN + TUD_AUDIO_DESC_STD_AS_ISO_EP_LEN +  \
     TUD_AUDIO_DESC_CS_AS_ISO_EP_LEN + TUD_AUDIO_DESC_STD_AS_ISO_FB_EP_LEN)
#define NXS_USB_AUDIO_DESCRIPTOR_LENGTH                                                                                                    \
    (TUD_AUDIO_DESC_IAD_LEN + TUD_AUDIO_DESC_STD_AC_LEN + TUD_AUDIO_DESC_CS_AC_LEN + TUD_AUDIO_DESC_CLK_SRC_LEN +                          \
     TUD_AUDIO_DESC_INPUT_TERM_LEN + TUD_AUDIO_DESC_OUTPUT_TERM_LEN + TUD_AUDIO_DESC_FEATURE_UNIT_TWO_CHANNEL_LEN +                        \
     TUD_AUDIO_DESC_STD_AS_INT_LEN + 2u * NXS_USB_STREAM_ALT_LENGTH)
#define NXS_USB_CONFIGURATION_LENGTH                                                                                                       \
    (TUD_CONFIG_DESC_LEN + NXS_USB_AUDIO_DESCRIPTOR_LENGTH + TUD_HID_DESC_LEN + NXS_USB_RESET_DESCRIPTOR_LENGTH)

typedef enum { NXS_USB_RESET_NONE, NXS_USB_RESET_BOOTSEL, NXS_USB_RESET_FLASH } nxs_usb_reset_action_t;
typedef struct {
    nxs_usb_reset_action_t action;
    uint8_t disable_mask;
} nxs_usb_reset_request_t;

nxs_usb_reset_request_t nxs_usb_pending_reset(void);

/** The validated serial string must remain alive for the USB session. */
void nxs_usb_set_serial(const char *serial);
/** Empty or NULL falls back to the fixed default string; the validated name must remain alive for the USB session. */
void nxs_usb_set_product_name(const char *name);
bool nxs_usb_init(const char *serial, const char *version);
bool nxs_usb_configure_storage(const nxs_storage_io_t *io, uint32_t flash_size_bytes, const nxs_stored_state_t *restored);
void nxs_usb_task(void);

#endif
