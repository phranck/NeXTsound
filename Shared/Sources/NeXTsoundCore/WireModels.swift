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
    public var requestID: UInt32
    public var generation: UInt32
    public var isResponse: Bool
    public var resultCode: UInt32
    public var payload: Data

    public init(operation: WireOperation, requestID: UInt32, generation: UInt32 = 0, payload: Data = Data()) {
        self.operation = operation
        self.requestID = requestID
        self.generation = generation
        self.payload = payload
        isResponse = false
        resultCode = NXS_RESULT_OK.rawValue
    }
}

public extension WireMessage {
    func validateResponse(to request: Self) throws {
        guard
            isResponse,
            !request.isResponse,
            operation == request.operation,
            requestID == request.requestID
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

    public var flashIsVerified: Bool {
        featureFlags & UInt16(NXS_FEATURE_FLASH_VERIFIED) != 0
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
