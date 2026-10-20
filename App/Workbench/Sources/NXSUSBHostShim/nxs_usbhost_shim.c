#include "nxs_usbhost_shim.h"
#include <libusb-1.0/libusb.h>

int nxs_libusb_open(uint16_t vendorID, uint16_t productID, void **outContext, void **outHandle) {
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

    *outContext = context;
    *outHandle = handle;
    return 0;
}

int nxs_libusb_exchange_feature_report(void *context, void *handle, uint16_t interfaceNumber, uint16_t reportValue,
                                       const uint8_t *setBuffer, uint8_t *getBuffer, size_t reportLength,
                                       unsigned int timeoutMilliseconds) {
    (void)context;
    libusb_device_handle *deviceHandle = (libusb_device_handle *)handle;

    int result = libusb_control_transfer(
        deviceHandle, LIBUSB_ENDPOINT_OUT | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE, 0x09, /* SET_REPORT */
        reportValue, interfaceNumber, (unsigned char *)setBuffer, (uint16_t)reportLength, timeoutMilliseconds);
    if (result < 0) {
        return result;
    }

    return libusb_control_transfer(deviceHandle, LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
                                   0x01, /* GET_REPORT */
                                   reportValue, interfaceNumber, getBuffer, (uint16_t)reportLength, timeoutMilliseconds);
}

void nxs_libusb_close(void *context, void *handle) {
    if (handle != NULL) {
        libusb_close((libusb_device_handle *)handle);
    }
    if (context != NULL) {
        libusb_exit((libusb_context *)context);
    }
}
