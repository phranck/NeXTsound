# RP2 ISO restart backport

`rp2040/dcd_rp2040.c` is byte-identical to TinyUSB commit [`102c1991d0abcfba9275830c48706ac34d7734d5`](https://github.com/hathach/tinyusb/commit/102c1991d0abcfba9275830c48706ac34d7734d5), dated March 5, 2025. SHA-256: `7bfdb2ae829d81371146511f205f1674c16428f7b9934a16152c9a6c06e86a75`.

The pinned SDK's TinyUSB revision leaves a pending ISO transfer armed when an endpoint is reactivated. The next transfer can hit the port's `was already available` panic. The upstream file aborts an active transfer before ISO reactivation and shares that abort operation with control-endpoint reset. Its original MIT notice is retained.

Firmware CMake replaces only this source in `tinyusb_device_base`; the SDK checkout, TinyUSB revision, common RP2 code, and other class drivers remain unchanged. Host tests compile this actual source and the pinned `rp2040_usb.c` against logical register fixtures. They check pending OUT/feedback transfers across 196/294-byte packet changes and repeated same-format activation, while preserving unrelated HID/control buffer state. They do not emulate USB timing or the complete controller. The unpatched source is retained as an expected-failure control.

When the SDK's pinned port gains this fix, remove this override and its expected-failure control instead of carrying two implementations. Confirm the regression on the new port and repeat the on-board format/lifecycle checks.
