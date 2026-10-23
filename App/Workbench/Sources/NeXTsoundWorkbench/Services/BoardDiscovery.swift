/// What the system reports about a SoundBox before the app talks to it: its USB vendor and product IDs and the
/// serial number it enumerated with.
public struct BoardIdentitySnapshot: Equatable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var enumeratedSerial: String?

    public init(vendorID: Int, productID: Int, enumeratedSerial: String? = nil) {
        self.vendorID = vendorID
        self.productID = productID
        self.enumeratedSerial = enumeratedSerial
    }
}

/// Finds SoundBoxes as they are plugged in and unplugged. `IOHIDBoardDiscovery` finds them through IOHIDManager, and
/// the tests pass a fake.
public protocol BoardDiscovery: Sendable {
    func start(
        onConnect: @escaping @Sendable (BoardIdentitySnapshot, any BoardTransport) -> Void,
        onDisconnect: @escaping @Sendable () -> Void
    )
    func stop()
}
