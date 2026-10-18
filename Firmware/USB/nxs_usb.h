#ifndef NXS_USB_H
#define NXS_USB_H

#include "nxs_audio.h"

#define NXS_USB_AUDIO_CONTROL_INTERFACE 0u
#define NXS_USB_AUDIO_STREAM_INTERFACE 1u
#define NXS_USB_HID_INTERFACE 2u
#define NXS_USB_INTERFACE_COUNT 3u
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
#define NXS_USB_CONFIGURATION_LENGTH (TUD_CONFIG_DESC_LEN + NXS_USB_AUDIO_DESCRIPTOR_LENGTH + TUD_HID_DESC_LEN)

/** The validated serial string must remain alive for the USB session. */
void nxs_usb_set_serial(const char *serial);
bool nxs_usb_init(const char *serial, const char *version);
void nxs_usb_task(void);

#endif
