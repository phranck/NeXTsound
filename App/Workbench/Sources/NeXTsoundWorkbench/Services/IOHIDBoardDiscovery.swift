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
        case .timeout: String(localized: "The board did not reply in time.")
        case .invalidReport: String(localized: "The capability report could not be built.")
        case let .transportFailed(code): String(localized: "The board rejected the request (code \(code)).")
        case .notConnected: String(localized: "No SoundBox is connected.")
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

/// Exchanges Feature reports (a `SET_REPORT` followed by its `GET_REPORT` reply) through a raw
/// USB class control transfer via libusb, rather than `IOHIDDeviceSetReport`/`GetReport` or
/// Apple's IOUSBHost framework. On this composite descriptor (Audio + HID + vendor reset),
/// `IOHIDDeviceGetReport`'s synchronous Feature-report path truncates the 255-byte reply to 1
/// byte and destabilizes the live USB connection; `IOUSBHostInterface`/`IOUSBHostDevice` both
/// require exclusive access to the interface or the whole device, which collides with CoreAudio
/// and the system HID driver already holding the other interfaces of this same device (issue
/// #22). libusb's control-transfer path does not require claiming anything, so it coexists with
/// both.
///
/// Keeps one libusb context and device handle open for the whole connection, opened lazily on
/// first use and closed on `deinit` (board disconnect), rather than reopened on every exchange.
/// Repeating libusb_init/open and libusb_close/exit around every single control transfer is both
/// the pattern libusb's own documentation discourages and, on this composite Audio + HID device,
/// a known source of fragile control-transfer behavior against Apple's own USB Audio kernel
/// extension, which can hold exclusive access to the device; a new connection's first exchange
/// opens a fresh context and handle again if an earlier open ever failed.
public final class USBHostBoardTransport: BoardTransport, @unchecked Sendable {
    private static let queue = DispatchQueue(label: "work.layered.NeXTsound.board-report")
    private static let timeout = Duration.seconds(2)

    private var context: UnsafeMutableRawPointer?
    private var handle: UnsafeMutableRawPointer?

    public init() {}

    deinit {
        if let context, let handle {
            nxs_libusb_close(context, handle)
        }
    }

    public func requestCapabilities() async throws -> DeviceCapabilities {
        let request = WireMessage(operation: .capabilities, requestID: .random(in: 1 ... .max))
        let message = try await exchange(request)
        return try WireCodec.decodeCapabilities(message.payload)
    }

    public func setDeviceName(_ name: String) async throws {
        let generation = try await currentGeneration()
        let payload = try WireCodec.encodeDeviceName(name)
        let request = WireMessage(operation: .setName, requestID: .random(in: 1 ... .max), generation: generation, payload: payload)
        _ = try await exchangeUntilComplete(request)
    }

    public func applyState(_ snapshot: DeviceSnapshot) async throws {
        let generation = try await currentGeneration()
        let payload = try WireCodec.encodeSnapshot(snapshot)
        let request = WireMessage(operation: .applyState, requestID: .random(in: 1 ... .max), generation: generation, payload: payload)
        _ = try await exchangeUntilComplete(request)
    }

    public func persistState() async throws {
        let generation = try await currentGeneration()
        let request = WireMessage(operation: .persistState, requestID: .random(in: 1 ... .max), generation: generation)
        _ = try await exchangeUntilComplete(request)
    }

    public func requestStatus() async throws -> BoardStatusReading {
        let message = try await exchange(WireMessage(operation: .status, requestID: .random(in: 1 ... .max)))
        let runtime = try WireCodec.decodeRuntimeStatus(message.payload)
        return BoardStatusReading(runtime: runtime, storage: BoardStorageState(activeGeneration: message.generation, status: runtime))
    }

    /// Both parts have to come from the same generation, because a write between the two reads would tear the block.
    public func requestMetadata() async throws -> OwnerMetadata {
        var block = Data()
        var generations = Set<UInt32>()
        for part in 0 ..< WireCodec.metadataPartCount {
            let request = WireMessage(
                operation: .readMetadata,
                requestID: .random(in: 1 ... .max),
                payload: WireCodec.metadataReadPayload(part: part)
            )
            let reply = try await exchange(request)
            block += reply.payload
            generations.insert(reply.generation)
        }
        guard generations.count == 1 else {
            throw BoardTransportError.invalidReport
        }
        return try WireCodec.decodeOwnerMetadata(block)
    }

    /// Part 0 replies at once; part 1 replies after the save, so both go through the polling exchange.
    public func writeMetadata(_ metadata: OwnerMetadata) async throws {
        let generation = try await currentGeneration()
        for payload in try WireCodec.metadataWritePayloads(metadata) {
            let request = WireMessage(
                operation: .writeMetadata,
                requestID: .random(in: 1 ... .max),
                generation: generation,
                payload: payload
            )
            _ = try await exchangeUntilComplete(request)
        }
    }
}

private extension USBHostBoardTransport {
    /// The firmware accepts a write only with the generation it currently plays, which every reply
    /// carries, so a write first asks for the capabilities to learn it.
    func currentGeneration() async throws -> UInt32 {
        try await exchange(WireMessage(operation: .capabilities, requestID: .random(in: 1 ... .max))).generation
    }

    func exchange(_ request: WireMessage) async throws -> WireMessage {
        let response = try await transfer(request)
        try response.validateResponse(to: request)
        return response
    }

    /// Polls for an operation's reply without resending it as a new request each time: the
    /// device replies to a persist/set-name request only once its flash write completes, which
    /// outlasts the request's own USB transaction, so the first few polls observe an unrelated
    /// reply still sitting in the device's response buffer. Resending the identical bytes is
    /// safe, because the device recognizes it as the same request already in flight.
    func exchangeUntilComplete(_ request: WireMessage, overallTimeout: Duration = .seconds(10)) async throws -> WireMessage {
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

    func transfer(_ request: WireMessage) async throws -> WireMessage {
        try await withThrowingTaskGroup(of: WireMessage.self) { group in
            group.addTask { try await self.transferOffQueue(request) }
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

    func transferOffQueue(_ request: WireMessage) async throws -> WireMessage {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                do {
                    try continuation.resume(returning: self.transferOnQueue(request))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Only ever called from `Self.queue`, so touching `context`/`handle` here without
    /// additional locking is safe: every exchange for this connection runs on that one queue.
    func transferOnQueue(_ request: WireMessage) throws -> WireMessage {
        if context == nil || handle == nil {
            var newContext: UnsafeMutableRawPointer?
            var newHandle: UnsafeMutableRawPointer?
            let openResult = nxs_libusb_open(UInt16(BoardIdentity.vendorID), UInt16(BoardIdentity.productID), &newContext, &newHandle)
            guard
                openResult == 0,
                let newContext,
                let newHandle
            else {
                throw BoardTransportError.transportFailed(Int32(openResult))
            }
            context = newContext
            handle = newHandle
        }

        let encoded = try WireCodec.encode(request)
        guard encoded.count == WireCodec.reportSize else {
            throw BoardTransportError.invalidReport
        }

        let reportValue = UInt16(WireCodec.reportID) | 0x0300
        var getBuffer = [UInt8](repeating: 0, count: WireCodec.reportSize)
        let bytesRead = encoded.withUnsafeBytes { setBuffer -> Int32 in
            getBuffer.withUnsafeMutableBufferPointer { getBuffer -> Int32 in
                nxs_libusb_exchange_feature_report(
                    context,
                    handle,
                    UInt16(BoardIdentity.hidInterfaceNumber),
                    reportValue,
                    setBuffer.bindMemory(to: UInt8.self).baseAddress,
                    getBuffer.baseAddress,
                    getBuffer.count,
                    UInt32(Self.timeout.components.seconds * 1000)
                )
            }
        }
        guard bytesRead == WireCodec.reportSize else {
            throw BoardTransportError.transportFailed(bytesRead)
        }

        return try WireCodec.decode(Data(getBuffer))
    }
}
