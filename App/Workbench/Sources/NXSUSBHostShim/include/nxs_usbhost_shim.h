#ifndef NXS_USBHOST_SHIM_H
#define NXS_USBHOST_SHIM_H

#include <stddef.h>
#include <stdint.h>

/// Opens a persistent libusb context and device handle for one connected board, kept open for
/// the connection's lifetime rather than reopened on every exchange. Calling libusb_init/open
/// and libusb_close/exit around every single control transfer is both the pattern libusb's own
/// documentation discourages and, on a composite device that also exposes a USB Audio Class
/// interface, a known source of fragile control-transfer behavior against Apple's own USB Audio
/// kernel extension, which can hold exclusive access to the device.
///
/// Returns 0 on success, with `*outContext`/`*outHandle` set to opaque pointers to pass to the
/// other functions here, or a negative libusb error code (see `libusb.h`) on failure, in which
/// case neither output pointer is written.
int nxs_libusb_open(uint16_t vendorID, uint16_t productID, void **outContext, void **outHandle);

/// Exchanges one HID Feature report (a SET_REPORT followed by a GET_REPORT) via a raw USB class
/// control transfer, on an already-open connection from `nxs_libusb_open`.
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
int nxs_libusb_exchange_feature_report(void *context, void *handle, uint16_t interfaceNumber, uint16_t reportValue,
                                       const uint8_t *setBuffer, uint8_t *getBuffer, size_t reportLength, unsigned int timeoutMilliseconds);

/// Closes a connection opened by `nxs_libusb_open`. Safe to call with NULL pointers.
void nxs_libusb_close(void *context, void *handle);

#endif
