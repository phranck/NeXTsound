import Foundation
@preconcurrency import IOKit.hid
import NeXTsoundCore

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
/// through `IOHIDBoardTransport`.
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
        instance.onConnect?(identity, IOHIDBoardTransport(device: device))
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
public struct IOHIDBoardTransport: BoardTransport, @unchecked Sendable {
    let device: IOHIDDevice

    private static let queue = DispatchQueue(label: "work.layered.NeXTsound.board-report")
    private static let timeout = Duration.seconds(2)

    public func requestCapabilities() async throws -> DeviceCapabilities {
        nonisolated(unsafe) let device = device
        let message = try await withThrowingTaskGroup(of: WireMessage.self) { group in
            group.addTask { try await Self.exchange(device: device) }
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

private extension IOHIDBoardTransport {
    /// The IOHIDDevice Set/GetReport buffer excludes the leading report-ID byte; the ID is passed
    /// separately. `WireCodec` bakes that same ID byte into byte 0 of its 256-byte wire image, so the
    /// body sent/received here is that image's remaining 255 bytes.
    static func exchange(device: IOHIDDevice) async throws -> WireMessage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try continuation.resume(returning: exchangeOnQueue(device: device))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func exchangeOnQueue(device: IOHIDDevice) throws -> WireMessage {
        let request = WireMessage(operation: .capabilities, requestID: .random(in: 1 ... .max))
        let encoded = try WireCodec.encode(request)
        guard encoded.count == WireCodec.reportSize else {
            throw BoardTransportError.invalidReport
        }
        let reportID = CFIndex(encoded[0])
        let body = Array(encoded.dropFirst())

        let setResult = try body.withUnsafeBufferPointer { buffer -> IOReturn in
            guard let baseAddress = buffer.baseAddress else {
                throw BoardTransportError.invalidReport
            }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, reportID, baseAddress, buffer.count)
        }
        guard setResult == kIOReturnSuccess else {
            throw BoardTransportError.transportFailed(setResult)
        }

        var responseBody = [UInt8](repeating: 0, count: WireCodec.reportSize - 1)
        var responseLength = responseBody.count
        let getResult = try responseBody.withUnsafeMutableBufferPointer { buffer -> IOReturn in
            guard let baseAddress = buffer.baseAddress else {
                throw BoardTransportError.invalidReport
            }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, reportID, baseAddress, &responseLength)
        }
        guard getResult == kIOReturnSuccess else {
            throw BoardTransportError.transportFailed(getResult)
        }
        guard responseLength > 0 else {
            throw BoardTransportError.invalidReport
        }

        var reportBytes = [UInt8](repeating: 0, count: WireCodec.reportSize)
        reportBytes[0] = UInt8(reportID)
        reportBytes.replaceSubrange(1 ..< (1 + responseLength), with: responseBody.prefix(responseLength))
        let response = try WireCodec.decode(Data(reportBytes))
        try response.validateResponse(to: request)
        return response
    }
}
