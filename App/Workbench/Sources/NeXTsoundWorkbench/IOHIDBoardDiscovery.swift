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
        instance.onConnect?(identity, USBHostBoardTransport(device: device))
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
/// Uses raw USB control transfers against the HID interface's default control endpoint rather than
/// `IOHIDDeviceSetReport`/`GetReport`. On this composite descriptor (Audio + HID + vendor reset),
/// `IOHIDDeviceGetReport`'s synchronous Feature-report path truncates the 255-byte reply to 1 byte and
/// destabilizes the live USB connection (issue #22); a class-specific control transfer carrying the full
/// 256-byte report, including the report-ID byte, does not. `IOUSBHostObject.sendDeviceRequest` is marked
/// `NS_REFINED_FOR_SWIFT` but Apple never shipped the promised overlay, so `NXSUSBHostInterfaceShim`
/// (a tiny Objective-C class in the NXSUSBHostShim target) re-exposes the same method as an ordinary
/// Swift-callable one.
public struct USBHostBoardTransport: BoardTransport, @unchecked Sendable {
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

private extension USBHostBoardTransport {
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

        let hostInterface = try openInterface(device: device)
        let wValue = UInt16(WireCodec.reportID) | 0x0300
        let wIndex = UInt16(BoardIdentity.hidInterfaceNumber)

        let setRequest = IOUSBDeviceRequest(bmRequestType: 0x21, bRequest: 9, wValue: wValue, wIndex: wIndex, wLength: UInt16(encoded.count))
        var setBytesTransferred: UInt = 0
        try NXSUSBHostInterfaceShim.sendDeviceRequest(
            setRequest,
            to: hostInterface,
            data: NSMutableData(data: encoded),
            bytesTransferred: &setBytesTransferred,
            completionTimeout: 2.0
        )
        guard setBytesTransferred == encoded.count else {
            throw BoardTransportError.invalidReport
        }

        guard let getData = NSMutableData(length: WireCodec.reportSize) else {
            throw BoardTransportError.invalidReport
        }
        let getRequest = IOUSBDeviceRequest(bmRequestType: 0xa1, bRequest: 1, wValue: wValue, wIndex: wIndex, wLength: UInt16(WireCodec.reportSize))
        var getBytesTransferred: UInt = 0
        try NXSUSBHostInterfaceShim.sendDeviceRequest(
            getRequest,
            to: hostInterface,
            data: getData,
            bytesTransferred: &getBytesTransferred,
            completionTimeout: 2.0
        )
        guard getBytesTransferred == WireCodec.reportSize else {
            throw BoardTransportError.invalidReport
        }

        let response = try WireCodec.decode(getData as Data)
        try response.validateResponse(to: request)
        return response
    }

    static func openInterface(device: IOHIDDevice) throws -> IOUSBHostInterface {
        let service = IOHIDDeviceGetService(device)
        guard service != IO_OBJECT_NULL else {
            throw BoardTransportError.invalidReport
        }
        return try IOUSBHostInterface(__ioService: service, options: [], queue: queue, interestHandler: nil)
    }
}
