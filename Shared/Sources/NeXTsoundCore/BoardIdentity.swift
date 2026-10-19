import NeXTsoundProtocol

/// The USB/HID identity constants from the canonical protocol header, exposed for board discovery.
public enum BoardIdentity {
    public static let vendorID = Int(NXS_USB_VENDOR_ID)
    public static let productID = Int(NXS_USB_PRODUCT_ID)
    public static let usagePage = Int(NXS_HID_USAGE_PAGE)
    public static let usage = Int(NXS_HID_USAGE)
    public static let hidInterfaceNumber = Int(NXS_USB_HID_INTERFACE)
}
