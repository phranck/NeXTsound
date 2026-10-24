import Foundation
import NeXTsoundProtocol

public struct WireError: Error, Equatable, LocalizedError, Sendable {
    public let code: UInt32

    public var errorDescription: String? {
        String(cString: nxs_result_description(nxs_result_t(rawValue: code)))
    }

    init(result: nxs_result_t) {
        code = result.rawValue
    }
}

public enum WireOperation: CaseIterable, Equatable, Sendable {
    case capabilities
    case readState
    case applyState
    case persistState
    case status
    case setName
    case diagnostics
    case readMetadata
    case writeMetadata
}

extension WireOperation {
    var protocolValue: nxs_operation_t {
        switch self {
        case .capabilities: NXS_OPERATION_CAPABILITIES
        case .readState: NXS_OPERATION_READ_STATE
        case .applyState: NXS_OPERATION_APPLY_STATE
        case .persistState: NXS_OPERATION_PERSIST_STATE
        case .status: NXS_OPERATION_STATUS
        case .setName: NXS_OPERATION_SET_NAME
        case .diagnostics: NXS_OPERATION_DIAGNOSTICS
        case .readMetadata: NXS_OPERATION_READ_METADATA
        case .writeMetadata: NXS_OPERATION_WRITE_METADATA
        }
    }

    init(protocolValue: nxs_operation_t) throws {
        guard let operation = Self.allCases.first(where: { $0.protocolValue == protocolValue }) else {
            throw WireError(result: NXS_RESULT_UNKNOWN_OPERATION)
        }
        self = operation
    }
}

public struct WireMessage: Equatable, Sendable {
    public var operation: WireOperation
    public var protocolMinor: UInt8
    public var requestID: UInt32
    public var generation: UInt32
    public var isResponse: Bool
    public var resultCode: UInt32
    public var payload: Data

    public init(
        operation: WireOperation,
        requestID: UInt32,
        generation: UInt32 = 0,
        payload: Data = Data(),
        protocolMinor: UInt8 = UInt8(NXS_PROTOCOL_MINOR)
    ) {
        self.operation = operation
        self.protocolMinor = protocolMinor
        self.requestID = requestID
        self.generation = generation
        self.payload = payload
        isResponse = false
        resultCode = NXS_RESULT_OK.rawValue
    }
}

public extension WireMessage {
    /// True once this reply's identity matches the request, regardless of its result code.
    /// An operation that completes asynchronously on the device (persist, set name) replies
    /// later than its own USB transaction, so a poll may observe an unrelated reply first.
    func matchesRequest(_ request: Self) -> Bool {
        isResponse && !request.isResponse && operation == request.operation && requestID == request.requestID
    }

    func validateResponse(to request: Self) throws {
        guard
            matchesRequest(request),
            protocolMinor == request.protocolMinor
        else {
            throw WireError(result: NXS_RESULT_INVALID_REPORT)
        }
        guard resultCode == NXS_RESULT_OK.rawValue else {
            throw WireError(result: nxs_result_t(rawValue: resultCode))
        }
    }
}

public struct DeviceSnapshot: Equatable, Sendable {
    public var profileID: UUID
    public var profileRevision: UInt32
    public var settings: DSPSettings

    public init(profileID: UUID, profileRevision: UInt32, settings: DSPSettings) {
        self.profileID = profileID
        self.profileRevision = profileRevision
        self.settings = settings
    }
}

public struct DeviceCapabilities: Equatable, Sendable {
    public var serial: String
    public var firmwareVersion: String
    /// Empty when no custom name is stored yet; see WireOperation.setName.
    public var deviceName: String
    public var sampleRateHz: UInt32
    public var systemClockHz: UInt32
    public var flashSizeBytes: UInt32
    public var bandCount: UInt8
    public var sampleFormatMask: UInt8
    public var featureFlags: UInt16
    public var parameterRanges: [DSPParameter: ClosedRange<Float>]

    public var supportsPersistence: Bool {
        featureFlags & UInt16(NXS_FEATURE_PERSISTENCE) != 0
    }

    public var supportsDiagnostics: Bool {
        featureFlags & UInt16(NXS_FEATURE_DIAGNOSTICS) != 0
    }

    /// Whether the board reads and writes owner metadata; see `OwnerMetadata`.
    public var supportsMetadata: Bool {
        featureFlags & UInt16(NXS_FEATURE_METADATA) != 0
    }

    public var flashIsVerified: Bool {
        featureFlags & UInt16(NXS_FEATURE_FLASH_VERIFIED) != 0
    }

    /// The PCM sample sizes the board's USB audio accepts, in bits, smallest first.
    public var sampleBits: [Int] {
        [(NXS_FORMAT_PCM16, 16), (NXS_FORMAT_PCM24, 24)].compactMap { flag, bits in
            sampleFormatMask & UInt8(flag) != 0 ? bits : nil
        }
    }

    public init(serial: String, firmwareVersion: String, deviceName: String = "") {
        self.serial = serial
        self.firmwareVersion = firmwareVersion
        self.deviceName = deviceName
        sampleRateHz = UInt32(NXS_SAMPLE_RATE_HZ)
        systemClockHz = UInt32(NXS_SYSTEM_CLOCK_HZ)
        flashSizeBytes = 0
        bandCount = UInt8(NXS_EQ_BAND_COUNT)
        sampleFormatMask = UInt8(NXS_FORMAT_PCM16 | NXS_FORMAT_PCM24)
        featureFlags = 0
        parameterRanges = Dictionary(uniqueKeysWithValues: DSPParameter.allCases.map { ($0, $0.bounds) })
    }
}

public struct DeviceRuntimeStatus: Equatable, Sendable {
    public var persistedGeneration: UInt32
    public var underrunCount: UInt32
    public var overrunCount: UInt32
    public var maxProcessingUs: UInt32
    public var blockDeadlineUs: UInt32
    public var inputPeak: Float
    public var outputPeak: Float
    public var hostVolumeDb: Float
    public var isStreaming: Bool
    public var hostIsMuted: Bool
    public var storageIsAvailable: Bool

    public init() {
        persistedGeneration = 0
        underrunCount = 0
        overrunCount = 0
        maxProcessingUs = 0
        blockDeadlineUs = 0
        inputPeak = 0
        outputPeak = 0
        hostVolumeDb = 0
        isStreaming = false
        hostIsMuted = false
        storageIsAvailable = false
    }
}

public struct DeviceRuntimeDiagnostics: Equatable, Sendable {
    public var ringUnderrunCount: UInt32
    public var i2sStallCount: UInt32
    public var rejectedPacketCount: UInt32
    public var dspFailureCount: UInt32
    public var deadlineMissCount: UInt32
    public var usbSuspendCount: UInt32
    public var usbResumeCount: UInt32

    public init() {
        ringUnderrunCount = 0
        i2sStallCount = 0
        rejectedPacketCount = 0
        dspFailureCount = 0
        deadlineMissCount = 0
        usbSuspendCount = 0
        usbResumeCount = 0
    }
}

/// A calendar day as the board stores it: year, month and day, without a time or a time zone.
public struct CalendarDay: Equatable, Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

/// The owner's metadata about one board, which the board keeps in flash beside its profile and name. The shared C codec
/// decides what is valid, so the app and the firmware refuse the same values.
public struct OwnerMetadata: Equatable, Sendable {
    /// A day the owner chose, or nil when unset.
    public var date: CalendarDay?
    /// The number the app shows after the prefix NXSB, from 0 to `NXS_SERIAL_NUMBER_MAX`, or nil when unset.
    public var serialNumber: UInt32?
    /// The owner's name, at most 64 bytes of UTF-8 without control characters.
    public var owner: String
    /// A free-text note, at most 256 bytes of UTF-8; line feeds are its only control characters.
    public var note: String

    /// The largest serial number the board stores.
    public static let maximumSerialNumber = UInt32(NXS_SERIAL_NUMBER_MAX)
    /// The owner's room in UTF-8 bytes.
    public static let ownerByteLimit = Int(NXS_OWNER_NAME_LENGTH)
    /// The note's room in UTF-8 bytes.
    public static let noteByteLimit = Int(NXS_OWNER_NOTE_LENGTH)

    public init(date: CalendarDay? = nil, serialNumber: UInt32? = nil, owner: String = "", note: String = "") {
        self.date = date
        self.serialNumber = serialNumber
        self.owner = owner
        self.note = note
    }
}
