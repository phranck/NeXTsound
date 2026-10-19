#ifndef NXS_USBHOST_SHIM_H
#define NXS_USBHOST_SHIM_H

#include <stddef.h>
#include <stdint.h>

/// Exchanges one HID Feature report (a SET_REPORT followed by a GET_REPORT) via a raw USB class
/// control transfer, through libusb rather than Apple's IOUSBHost framework.
///
/// This device exposes USB Audio, HID, and a vendor reset interface at once. Apple's IOUSBHost
/// framework always opens either a whole device (IOUSBHostDevice) or a single interface
/// (IOUSBHostInterface) exclusively, which collides with CoreAudio already holding the Audio
/// interfaces and the system HID driver already holding the HID interface (see issue #22).
/// libusb's control-transfer path on macOS does not require claiming any interface, so it
/// coexists with both of those without seizing or disrupting them.
///
/// Returns the number of bytes read back on success (normally `reportLength`), or a negative
/// libusb error code (see `libusb.h`) on failure.
int nxs_libusb_exchange_feature_report(
    uint16_t vendorID,
    uint16_t productID,
    uint16_t interfaceNumber,
    uint16_t reportValue,
    const uint8_t *setBuffer,
    uint8_t *getBuffer,
    size_t reportLength,
    unsigned int timeoutMilliseconds
);

#endif
