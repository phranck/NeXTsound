import Foundation
@preconcurrency import IOKit.hid
import NeXTsoundCore
import NXSUSBHostShim

public enum BoardTransportError: Error, Equatable, LocalizedError, Sendable {
    case timeout
    case invalidReport
    case transportFailed(Int32)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .timeout: "The board did not reply in time."
        case .invalidReport: "The capability report could not be built."
        case let .transportFailed(code): "The board rejected the request (code \(code))."
        case .notConnected: "No SoundBox is connected."
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
        let request = WireMessage(operation: .capabilities, requestID: .random(in: 1 ... .max))
        let message = try await Self.exchange(request)
        return try WireCodec.decodeCapabilities(message.payload)
    }

    public func setDeviceName(_ name: String) async throws {
        let current = try await Self.exchange(WireMessage(operation: .capabilities, requestID: .random(in: 1 ... .max)))
        let payload = try WireCodec.encodeDeviceName(name)
        let request = WireMessage(operation: .setName, requestID: .random(in: 1 ... .max), generation: current.generation, payload: payload)
        _ = try await Self.exchangeUntilComplete(request)
    }
}

private extension USBHostBoardTransport {
    static func exchange(_ request: WireMessage) async throws -> WireMessage {
        let response = try await transfer(request)
        try response.validateResponse(to: request)
        return response
    }

    /// Polls for an operation's reply without resending it as a new request each time: the
    /// device replies to a persist/set-name request only once its flash write completes, which
    /// outlasts the request's own USB transaction, so the first few polls observe an unrelated
    /// reply still sitting in the device's response buffer. Resending the identical bytes is
    /// safe, because the device recognizes it as the same request already in flight.
    static func exchangeUntilComplete(_ request: WireMessage, overallTimeout: Duration = .seconds(10)) async throws -> WireMessage {
        let deadline = ContinuousClock.now + overallTimeout
        while true {
            let response = try await transfer(request)
            if response.matchesRequest(request) {
                try response.validateResponse(to: request)
                return response
            }
            guard ContinuousClock.now < deadline else {
                throw BoardTransportError.timeout
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    static func transfer(_ request: WireMessage) async throws -> WireMessage {
        try await withThrowingTaskGroup(of: WireMessage.self) { group in
            group.addTask { try await Self.transferOffQueue(request) }
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
    }

    static func transferOffQueue(_ request: WireMessage) async throws -> WireMessage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try continuation.resume(returning: transferOnQueue(request))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func transferOnQueue(_ request: WireMessage) throws -> WireMessage {
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

        return try WireCodec.decode(Data(getBuffer))
    }
}
