#include "nxs_usbhost_shim.h"
#include <libusb-1.0/libusb.h>

int nxs_libusb_exchange_feature_report(
    uint16_t vendorID,
    uint16_t productID,
    uint16_t interfaceNumber,
    uint16_t reportValue,
    const uint8_t *setBuffer,
    uint8_t *getBuffer,
    size_t reportLength,
    unsigned int timeoutMilliseconds
) {
    libusb_context *context = NULL;
    int result = libusb_init(&context);
    if (result < 0) {
        return result;
    }

    libusb_device_handle *handle = libusb_open_device_with_vid_pid(context, vendorID, productID);
    if (handle == NULL) {
        libusb_exit(context);
        return LIBUSB_ERROR_NO_DEVICE;
    }

    result = libusb_control_transfer(
        handle,
        LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        0x09, /* SET_REPORT */
        reportValue,
        interfaceNumber,
        (unsigned char *)setBuffer,
        (uint16_t)reportLength,
        timeoutMilliseconds
    );
    if (result < 0) {
        libusb_close(handle);
        libusb_exit(context);
        return result;
    }

    result = libusb_control_transfer(
        handle,
        LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        0x01, /* GET_REPORT */
        reportValue,
        interfaceNumber,
        getBuffer,
        (uint16_t)reportLength,
        timeoutMilliseconds
    );

    libusb_close(handle);
    libusb_exit(context);
    return result;
}
