import Foundation
@preconcurrency import IOKit.hid
import NeXTsoundCore
import NXSUSBHostShim

public enum BoardTransportError: Error, Equatable, LocalizedError, Sendable {
    case timeout
    case invalidReport
    case transportFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .timeout: "The board did not reply in time."
        case .invalidReport: "The capability report could not be built."
        case let .transportFailed(code): "The board rejected the capability request (code \(code))."
        }
    }
}

/// Discovers compatible SoundBoxes through IOHIDManager without seizing them. Matching/removal
/// notifications run on the main run loop; the blocking report exchange itself runs off-thread
/// through `USBHostBoardTransport`.
public final class IOHIDBoardDiscovery: BoardDiscovery, @unchecked Sendable {
    private let manager: IOHIDManager
    private var onConnect: (@Sendable (BoardIdentitySnapshot, any BoardTransport) -> Void)?
    private var onDisconnect: (@Sendable () -> Void)?

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: BoardIdentity.vendorID,
            kIOHIDProductIDKey: BoardIdentity.productID,
            kIOHIDPrimaryUsagePageKey: BoardIdentity.usagePage,
            kIOHIDPrimaryUsageKey: BoardIdentity.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    }
}

public extension IOHIDBoardDiscovery {
    func start(
        onConnect: @escaping @Sendable (BoardIdentitySnapshot, any BoardTransport) -> Void,
        onDisconnect: @escaping @Sendable () -> Void
    ) {
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.removalCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func stop() {
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        onConnect = nil
        onDisconnect = nil
    }
}

private extension IOHIDBoardDiscovery {
    static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else {
            return
        }
        let instance = Unmanaged<IOHIDBoardDiscovery>.fromOpaque(context).takeUnretainedValue()
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
        let identity = BoardIdentitySnapshot(vendorID: BoardIdentity.vendorID, productID: BoardIdentity.productID, enumeratedSerial: serial)
        instance.onConnect?(identity, USBHostBoardTransport())
    }

    static let removalCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else {
            return
        }
        let instance = Unmanaged<IOHIDBoardDiscovery>.fromOpaque(context).takeUnretainedValue()
        instance.onDisconnect?()
    }
}

/// Exchanges exactly one Feature report per call: a capabilities `SET_REPORT` followed by its `GET_REPORT` reply.
///
/// Uses a raw USB class control transfer through libusb rather than `IOHIDDeviceSetReport`/`GetReport`
/// or Apple's IOUSBHost framework. On this composite descriptor (Audio + HID + vendor reset),
/// `IOHIDDeviceGetReport`'s synchronous Feature-report path truncates the 255-byte reply to 1 byte and
/// destabilizes the live USB connection; `IOUSBHostInterface`/`IOUSBHostDevice` both require exclusive
/// access to the interface or the whole device, which collides with CoreAudio and the system HID driver
/// already holding the other interfaces of this same device (issue #22). libusb's control-transfer path
/// does not require claiming anything, so it coexists with both.
public struct USBHostBoardTransport: BoardTransport, @unchecked Sendable {
    private static let queue = DispatchQueue(label: "work.layered.NeXTsound.board-report")
    private static let timeout = Duration.seconds(2)

    public init() {}

    public func requestCapabilities() async throws -> DeviceCapabilities {
        let message = try await withThrowingTaskGroup(of: WireMessage.self) { group in
            group.addTask { try await Self.exchange() }
            group.addTask {
                try await Task.sleep(for: Self.timeout)
                throw BoardTransportError.timeout
            }
            guard let result = try await group.next() else {
                throw BoardTransportError.timeout
            }
            group.cancelAll()
            return result
        }
        return try WireCodec.decodeCapabilities(message.payload)
    }
}

private extension USBHostBoardTransport {
    static func exchange() async throws -> WireMessage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try continuation.resume(returning: exchangeOnQueue())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func exchangeOnQueue() throws -> WireMessage {
        let request = WireMessage(operation: .capabilities, requestID: .random(in: 1 ... .max))
        let encoded = try WireCodec.encode(request)
        guard encoded.count == WireCodec.reportSize else {
            throw BoardTransportError.invalidReport
        }

        let reportValue = UInt16(WireCodec.reportID) | 0x0300
        var getBuffer = [UInt8](repeating: 0, count: WireCodec.reportSize)
        let bytesRead = encoded.withUnsafeBytes { setBuffer -> Int32 in
            getBuffer.withUnsafeMutableBufferPointer { getBuffer -> Int32 in
                nxs_libusb_exchange_feature_report(
                    UInt16(BoardIdentity.vendorID),
                    UInt16(BoardIdentity.productID),
                    UInt16(BoardIdentity.hidInterfaceNumber),
                    reportValue,
                    setBuffer.bindMemory(to: UInt8.self).baseAddress,
                    getBuffer.baseAddress,
                    getBuffer.count,
                    UInt32(timeout.components.seconds * 1000)
                )
            }
        }
        guard bytesRead == WireCodec.reportSize else {
            throw BoardTransportError.transportFailed(bytesRead)
        }

        let response = try WireCodec.decode(Data(getBuffer))
        try response.validateResponse(to: request)
        return response
    }
}
