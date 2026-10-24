import Foundation
import NeXTsoundProtocol

public enum WireCodec {
    public static let reportSize = Int(NXS_REPORT_SIZE)
    public static let reportID = Int(NXS_REPORT_ID)
}

public extension WireCodec {
    static func encode(_ message: WireMessage) throws -> Data {
        guard message.payload.count <= Int(NXS_PAYLOAD_CAPACITY) else {
            throw WireError(result: NXS_RESULT_INVALID_REPORT)
        }
        var value = nxs_message_t()
        value.operation = message.operation.protocolValue
        value.protocol_minor = message.protocolMinor
        value.request_id = message.requestID
        value.generation = message.generation
        value.flags = message.isResponse ? UInt8(NXS_FLAG_RESPONSE) : 0
        value.result = nxs_result_t(rawValue: message.resultCode)
        value.payload_length = UInt16(message.payload.count)
        withUnsafeMutableBytes(of: &value.payload) { destination in
            destination.copyBytes(from: message.payload)
        }
        return try encoded(value, size: reportSize, using: nxs_message_encode)
    }

    static func decode(_ report: Data) throws -> WireMessage {
        let value = try decoded(report, size: reportSize, initial: nxs_message_t(), using: nxs_message_decode)
        let payload = withUnsafeBytes(of: value.payload) { bytes in
            Data(bytes.prefix(Int(value.payload_length)))
        }
        var message = try WireMessage(
            operation: WireOperation(protocolValue: value.operation),
            requestID: value.request_id,
            generation: value.generation,
            payload: payload,
            protocolMinor: value.protocol_minor
        )
        message.isResponse = value.flags & UInt8(NXS_FLAG_RESPONSE) != 0
        message.resultCode = value.result.rawValue
        return message
    }

    static func encodeSnapshot(_ snapshot: DeviceSnapshot) throws -> Data {
        let value = try snapshot.settings.protocolSnapshot(profileID: snapshot.profileID, revision: snapshot.profileRevision)
        return try encoded(value, size: Int(NXS_SNAPSHOT_SIZE), using: nxs_snapshot_encode)
    }

    static func decodeSnapshot(_ payload: Data) throws -> DeviceSnapshot {
        let value = try decoded(payload, size: Int(NXS_SNAPSHOT_SIZE), initial: nxs_default_snapshot(), using: nxs_snapshot_decode)
        return DeviceSnapshot(
            profileID: UUID(uuid: value.profile_id),
            profileRevision: value.profile_revision,
            settings: DSPSettings(protocolSnapshot: value)
        )
    }

    static func encodeCapabilities(_ capabilities: DeviceCapabilities) throws -> Data {
        var value = nxs_default_capabilities()
        value.sample_rate_hz = capabilities.sampleRateHz
        value.system_clock_hz = capabilities.systemClockHz
        value.flash_size_bytes = capabilities.flashSizeBytes
        value.eq_band_count = capabilities.bandCount
        value.sample_format_mask = capabilities.sampleFormatMask
        value.feature_flags = capabilities.featureFlags
        try writeString(capabilities.serial, to: &value.device_serial)
        try writeString(capabilities.firmwareVersion, to: &value.firmware_version)
        try writeString(capabilities.deviceName, to: &value.device_name)
        try withUnsafeMutableBytes(of: &value.ranges) { bytes in
            let destination = bytes.bindMemory(to: nxs_parameter_range_t.self)
            for parameter in DSPParameter.allCases {
                guard let range = capabilities.parameterRanges[parameter] else {
                    throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
                }
                destination[Int(parameter.protocolValue.rawValue)] = nxs_parameter_range_t(
                    minimum: range.lowerBound,
                    maximum: range.upperBound
                )
            }
        }
        return try encoded(value, size: Int(NXS_CAPABILITIES_SIZE), using: nxs_capabilities_encode)
    }

    static func decodeCapabilities(_ payload: Data) throws -> DeviceCapabilities {
        let value = try decoded(
            payload,
            size: Int(NXS_CAPABILITIES_SIZE),
            initial: nxs_default_capabilities(),
            using: nxs_capabilities_decode
        )
        var capabilities = try DeviceCapabilities(
            serial: readString(value.device_serial),
            firmwareVersion: readString(value.firmware_version),
            deviceName: readString(value.device_name)
        )
        capabilities.sampleRateHz = value.sample_rate_hz
        capabilities.systemClockHz = value.system_clock_hz
        capabilities.flashSizeBytes = value.flash_size_bytes
        capabilities.bandCount = value.eq_band_count
        capabilities.sampleFormatMask = value.sample_format_mask
        capabilities.featureFlags = value.feature_flags
        capabilities.parameterRanges = withUnsafeBytes(of: value.ranges) { bytes in
            let ranges = bytes.bindMemory(to: nxs_parameter_range_t.self)
            return Dictionary(uniqueKeysWithValues: DSPParameter.allCases.map { parameter in
                let range = ranges[Int(parameter.protocolValue.rawValue)]
                return (parameter, range.minimum ... range.maximum)
            })
        }
        return capabilities
    }

    static func encodeRuntimeStatus(_ status: DeviceRuntimeStatus) throws -> Data {
        let value = nxs_runtime_status_t(
            persisted_generation: status.persistedGeneration,
            underrun_count: status.underrunCount,
            overrun_count: status.overrunCount,
            max_processing_us: status.maxProcessingUs,
            block_deadline_us: status.blockDeadlineUs,
            input_peak: status.inputPeak,
            output_peak: status.outputPeak,
            host_volume_db: status.hostVolumeDb,
            streaming: status.isStreaming ? 1 : 0,
            host_muted: status.hostIsMuted ? 1 : 0,
            storage_available: status.storageIsAvailable ? 1 : 0
        )
        return try encoded(value, size: Int(NXS_RUNTIME_STATUS_SIZE), using: nxs_runtime_status_encode)
    }

    static func decodeRuntimeStatus(_ payload: Data) throws -> DeviceRuntimeStatus {
        let value = try decoded(
            payload,
            size: Int(NXS_RUNTIME_STATUS_SIZE),
            initial: nxs_runtime_status_t(),
            using: nxs_runtime_status_decode
        )
        var status = DeviceRuntimeStatus()
        status.persistedGeneration = value.persisted_generation
        status.underrunCount = value.underrun_count
        status.overrunCount = value.overrun_count
        status.maxProcessingUs = value.max_processing_us
        status.blockDeadlineUs = value.block_deadline_us
        status.inputPeak = value.input_peak
        status.outputPeak = value.output_peak
        status.hostVolumeDb = value.host_volume_db
        status.isStreaming = value.streaming != 0
        status.hostIsMuted = value.host_muted != 0
        status.storageIsAvailable = value.storage_available != 0
        return status
    }

    static func encodeRuntimeDiagnostics(_ diagnostics: DeviceRuntimeDiagnostics) throws -> Data {
        let value = nxs_runtime_diagnostics_t(
            ring_underrun_count: diagnostics.ringUnderrunCount,
            i2s_stall_count: diagnostics.i2sStallCount,
            rejected_packet_count: diagnostics.rejectedPacketCount,
            dsp_failure_count: diagnostics.dspFailureCount,
            deadline_miss_count: diagnostics.deadlineMissCount,
            usb_suspend_count: diagnostics.usbSuspendCount,
            usb_resume_count: diagnostics.usbResumeCount
        )
        return try encoded(value, size: Int(NXS_RUNTIME_DIAGNOSTICS_SIZE), using: nxs_runtime_diagnostics_encode)
    }

    static func decodeRuntimeDiagnostics(_ payload: Data) throws -> DeviceRuntimeDiagnostics {
        let value = try decoded(
            payload,
            size: Int(NXS_RUNTIME_DIAGNOSTICS_SIZE),
            initial: nxs_runtime_diagnostics_t(),
            using: nxs_runtime_diagnostics_decode
        )
        var diagnostics = DeviceRuntimeDiagnostics()
        diagnostics.ringUnderrunCount = value.ring_underrun_count
        diagnostics.i2sStallCount = value.i2s_stall_count
        diagnostics.rejectedPacketCount = value.rejected_packet_count
        diagnostics.dspFailureCount = value.dsp_failure_count
        diagnostics.deadlineMissCount = value.deadline_miss_count
        diagnostics.usbSuspendCount = value.usb_suspend_count
        diagnostics.usbResumeCount = value.usb_resume_count
        return diagnostics
    }

    static func encodeDeviceName(_ name: String) throws -> Data {
        var nameBuffer = [CChar](repeating: 0, count: Int(NXS_DEVICE_NAME_LENGTH))
        let bytes = Array(name.utf8)
        guard
            bytes.count < nameBuffer.count,
            !bytes.contains(0)
        else {
            throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
        }
        for (index, byte) in bytes.enumerated() {
            nameBuffer[index] = CChar(bitPattern: byte)
        }
        var payloadBytes = [UInt8](repeating: 0, count: Int(NXS_DEVICE_NAME_LENGTH))
        try nameBuffer.withUnsafeBufferPointer { namePointer in
            try payloadBytes.withUnsafeMutableBufferPointer { payloadPointer in
                try check(nxs_device_name_encode(namePointer.baseAddress, payloadPointer.baseAddress, payloadPointer.count))
            }
        }
        return Data(payloadBytes)
    }

    static func decodeDeviceName(_ payload: Data) throws -> String {
        guard payload.count == Int(NXS_DEVICE_NAME_LENGTH) else {
            throw WireError(result: NXS_RESULT_INVALID_REPORT)
        }
        var nameBuffer = [CChar](repeating: 0, count: Int(NXS_DEVICE_NAME_LENGTH))
        try payload.withUnsafeBytes { bytes in
            try nameBuffer.withUnsafeMutableBufferPointer { namePointer in
                guard let address = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    throw WireError(result: NXS_RESULT_INVALID_REPORT)
                }
                try check(nxs_device_name_decode(address, payload.count, namePointer.baseAddress))
            }
        }
        let terminatorIndex = nameBuffer.firstIndex(of: 0) ?? nameBuffer.count
        let utf8Bytes = nameBuffer[..<terminatorIndex].map { UInt8(bitPattern: $0) }
        guard let decoded = String(bytes: utf8Bytes, encoding: .utf8) else {
            throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
        }
        return decoded
    }

    /// How many parts the metadata block travels in, each in its own request.
    static let metadataPartCount = Int(NXS_METADATA_PART_COUNT)

    /// Encodes metadata into the `NXS_METADATA_SIZE` block, refusing what the C codec refuses: an impossible date, a serial
    /// number of zero or above `NXS_SERIAL_NUMBER_MAX`, text that does not fit, and control characters.
    static func encodeOwnerMetadata(_ metadata: OwnerMetadata) throws -> Data {
        var value = nxs_owner_metadata_t()
        if let date = metadata.date {
            guard
                (1 ... 9999).contains(date.year),
                (1 ... 12).contains(date.month),
                (1 ... 31).contains(date.day)
            else {
                throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
            }
            value.date = UInt32(date.year * 10000 + date.month * 100 + date.day)
        }
        if let serialNumber = metadata.serialNumber {
            guard serialNumber != 0 else {
                throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
            }
            value.serial_number = serialNumber
        }
        try writeString(metadata.owner, to: &value.owner, reservingTerminator: false)
        try writeString(metadata.note, to: &value.note, reservingTerminator: false)
        return try encoded(value, size: Int(NXS_METADATA_SIZE), using: nxs_owner_metadata_encode)
    }

    static func decodeOwnerMetadata(_ block: Data) throws -> OwnerMetadata {
        let value = try decoded(block, size: Int(NXS_METADATA_SIZE), initial: nxs_owner_metadata_t(), using: nxs_owner_metadata_decode)
        let date = value.date == 0 ? nil : CalendarDay(
            year: Int(value.date / 10000),
            month: Int(value.date / 100 % 100),
            day: Int(value.date % 100)
        )
        return try OwnerMetadata(
            date: date,
            serialNumber: value.serial_number == 0 ? nil : value.serial_number,
            owner: readString(value.owner),
            note: readString(value.note)
        )
    }

    /// The `readMetadata` request payload for one part: its index.
    static func metadataReadPayload(part: Int) -> Data {
        Data([UInt8(part)])
    }

    /// The `writeMetadata` request payloads, part 0 first: each is the part index, three zero bytes, then the part.
    static func metadataWritePayloads(_ metadata: OwnerMetadata) throws -> [Data] {
        let block = try encodeOwnerMetadata(metadata)
        let partSize = Int(NXS_METADATA_PART_SIZE)
        return (0 ..< metadataPartCount).map { part in
            Data([UInt8(part), 0, 0, 0]) + block.subdata(in: part * partSize ..< (part + 1) * partSize)
        }
    }
}

private extension WireCodec {
    static func check(_ result: nxs_result_t) throws {
        guard result == NXS_RESULT_OK else {
            throw WireError(result: result)
        }
    }

    static func encoded<Value>(
        _ value: Value,
        size: Int,
        using encoder: (UnsafePointer<Value>, UnsafeMutablePointer<UInt8>, Int) -> nxs_result_t
    ) throws -> Data {
        var source = value
        var bytes = [UInt8](repeating: 0, count: size)
        try bytes.withUnsafeMutableBufferPointer { destination in
            guard let address = destination.baseAddress else {
                throw WireError(result: NXS_RESULT_INVALID_REPORT)
            }
            try withUnsafePointer(to: &source) { pointer in
                try check(encoder(pointer, address, size))
            }
        }
        return Data(bytes)
    }

    static func decoded<Value>(
        _ payload: Data,
        size: Int,
        initial: Value,
        using decoder: (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<Value>) -> nxs_result_t
    ) throws -> Value {
        guard payload.count == size else {
            throw WireError(result: NXS_RESULT_INVALID_REPORT)
        }
        var value = initial
        try payload.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw WireError(result: NXS_RESULT_INVALID_REPORT)
            }
            try check(decoder(address, size, &value))
        }
        return value
    }

    static func readString(_ storage: some Any) throws -> String {
        let decoded = withUnsafeBytes(of: storage) { bytes in
            String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .utf8)
        }
        guard let decoded else {
            throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
        }
        return decoded
    }

    /// Copies the text's UTF-8 into a fixed field and zeroes the rest. Device strings keep room for a terminator; the
    /// metadata's text fields may fill their field completely.
    static func writeString(_ text: String, to storage: inout some Any, reservingTerminator: Bool = true) throws {
        let bytes = Array(text.utf8)
        try withUnsafeMutableBytes(of: &storage) { destination in
            guard
                bytes.count <= destination.count - (reservingTerminator ? 1 : 0),
                !bytes.contains(0)
            else {
                throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
            }
            for index in destination.indices {
                destination[index] = 0
            }
            destination.copyBytes(from: bytes)
        }
    }
}
