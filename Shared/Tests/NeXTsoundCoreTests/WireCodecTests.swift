import Foundation
import NeXTsoundProtocol
import Testing
@testable import NeXTsoundCore

struct WireCodecTests {
    @Test func matchesTheSharedGoldenPacket() throws {
        let fixtureURL = try #require(Bundle.module.url(
            forResource: "capabilities-request",
            withExtension: "hex",
            subdirectory: "Fixtures"
        ))
        let text = try String(contentsOf: fixtureURL, encoding: .utf8)
        let bytes = try text.split(whereSeparator: \.isWhitespace).map { token in
            try #require(UInt8(token, radix: 16))
        }
        #expect(bytes.count == WireCodec.reportSize)
        let request = WireMessage(operation: .capabilities, requestID: 0x0102_0304, generation: 0x1122_3344, protocolMinor: 0)
        #expect(try WireCodec.encode(request) == Data(bytes))
        #expect(try WireCodec.decode(Data(bytes)) == request)
    }

    @Test(arguments: [0, 1, 19, 20, 119, 255, 257, 512])
    func rejectsIncorrectReportLengths(_ length: Int) {
        #expect(throws: WireError.self) {
            try WireCodec.decode(Data(repeating: 0, count: length))
        }
    }

    @Test func rejectsUnknownVersionsAndDirtyPadding() throws {
        let request = WireMessage(operation: .readState, requestID: 1)
        var report = try WireCodec.encode(request)
        report[1] = 99
        #expect(throws: WireError(result: NXS_RESULT_UNSUPPORTED_VERSION)) {
            try WireCodec.decode(report)
        }
        report = try WireCodec.encode(request)
        report[report.count - 1] = 1
        #expect(throws: WireError.self) {
            try WireCodec.decode(report)
        }
    }

    @Test func rejectsOversizedPayloadAndInvalidRequestID() {
        let oversized = WireMessage(operation: .applyState, requestID: 1, payload: Data(repeating: 0, count: 100_000))
        #expect(throws: WireError.self) { try WireCodec.encode(oversized) }
        #expect(throws: WireError.self) { try WireCodec.encode(WireMessage(operation: .status, requestID: 0)) }
    }

    @Test func snapshotRoundTripPreservesIdentityAndParameters() throws {
        let identifier = try #require(UUID(uuidString: "00010203-0405-0607-0809-0A0B0C0D0E0F"))
        var settings = DSPSettings()
        settings.bands[2].gainDb = 3.5
        let snapshot = DeviceSnapshot(profileID: identifier, profileRevision: 17, settings: settings)
        let payload = try WireCodec.encodeSnapshot(snapshot)
        #expect(payload.prefix(16) == Data(0 ..< 16))
        #expect(try WireCodec.decodeSnapshot(payload) == snapshot)
        #expect(payload.count == Int(NXS_SNAPSHOT_SIZE))
    }

    @Test(arguments: [Float.nan, .infinity, -.infinity, 0, 25000])
    func rejectsInvalidFrequencies(_ frequency: Float) {
        var settings = DSPSettings()
        settings.bands[0].frequencyHz = frequency
        #expect(throws: WireError.self) { try settings.validate() }
    }

    @Test func rejectsTheWrongNumberOfBands() {
        var settings = DSPSettings()
        settings.bands.removeLast()
        #expect(throws: WireError.self) { try settings.validate() }
    }

    @Test func capabilityRoundTripUsesTheSharedBounds() throws {
        var capabilities = DeviceCapabilities(serial: "TESTDEVICE", firmwareVersion: "test")
        capabilities.flashSizeBytes = 4 * 1024 * 1024
        capabilities.featureFlags = UInt16(NXS_FEATURE_PERSISTENCE | NXS_FEATURE_FLASH_VERIFIED)
        let payload = try WireCodec.encodeCapabilities(capabilities)
        #expect(try WireCodec.decodeCapabilities(payload) == capabilities)
        #expect(capabilities.supportsPersistence)
        #expect(DSPParameter.allCases.count == Int(NXS_PARAMETER_COUNT.rawValue))
    }

    @Test func rejectsPersistenceWithoutVerifiedFlash() {
        var capabilities = DeviceCapabilities(serial: "TESTDEVICE", firmwareVersion: "test")
        capabilities.featureFlags = UInt16(NXS_FEATURE_PERSISTENCE)
        #expect(throws: WireError.self) { try WireCodec.encodeCapabilities(capabilities) }
    }

    @Test func rejectsEmbeddedNullsInDeviceStrings() {
        let capabilities = DeviceCapabilities(serial: "test\0hidden", firmwareVersion: "test")
        #expect(throws: WireError.self) { try WireCodec.encodeCapabilities(capabilities) }
    }

    @Test func capabilityRoundTripPreservesTheDeviceName() throws {
        let capabilities = DeviceCapabilities(serial: "TESTDEVICE", firmwareVersion: "test", deviceName: "Bedroom SoundBox")
        let payload = try WireCodec.encodeCapabilities(capabilities)
        #expect(try WireCodec.decodeCapabilities(payload).deviceName == "Bedroom SoundBox")
    }

    @Test func capabilityRoundTripAllowsAnEmptyDeviceName() throws {
        let capabilities = DeviceCapabilities(serial: "TESTDEVICE", firmwareVersion: "test")
        let payload = try WireCodec.encodeCapabilities(capabilities)
        #expect(try WireCodec.decodeCapabilities(payload).deviceName.isEmpty)
    }

    @Test func deviceNameRoundTripPreservesSpacesAndClearsPadding() throws {
        let payload = try WireCodec.encodeDeviceName("Bedroom SoundBox")
        #expect(payload.count == Int(NXS_DEVICE_NAME_LENGTH))
        #expect(try WireCodec.decodeDeviceName(payload) == "Bedroom SoundBox")
    }

    @Test func deviceNameRejectsEmbeddedNullsAndOversizedNames() {
        #expect(throws: WireError.self) { try WireCodec.encodeDeviceName("test\0hidden") }
        #expect(throws: WireError.self) { try WireCodec.encodeDeviceName(String(repeating: "A", count: Int(NXS_DEVICE_NAME_LENGTH))) }
    }

    @Test func deviceNameDecodeRejectsTheWrongPayloadLength() {
        #expect(throws: WireError.self) { try WireCodec.decodeDeviceName(Data(repeating: 0, count: Int(NXS_DEVICE_NAME_LENGTH) - 1)) }
    }

    @Test func runtimeStatusRoundTripPreservesDiagnostics() throws {
        var status = DeviceRuntimeStatus()
        status.persistedGeneration = 20
        status.maxProcessingUs = 150
        status.blockDeadlineUs = 1000
        status.inputPeak = 0.8
        status.outputPeak = 0.3
        status.hostVolumeDb = -12
        status.isStreaming = true
        status.storageIsAvailable = true
        #expect(try WireCodec.decodeRuntimeStatus(WireCodec.encodeRuntimeStatus(status)) == status)
    }

    @Test func diagnosticRoundTripAndVersionValidation() throws {
        var diagnostics = DeviceRuntimeDiagnostics()
        diagnostics.ringUnderrunCount = 0x1234_5678
        diagnostics.i2sStallCount = 2
        diagnostics.rejectedPacketCount = .max
        diagnostics.dspFailureCount = 4
        diagnostics.deadlineMissCount = 5
        diagnostics.usbSuspendCount = 6
        diagnostics.usbResumeCount = 7
        var payload = try WireCodec.encodeRuntimeDiagnostics(diagnostics)
        #expect(payload.count == Int(NXS_RUNTIME_DIAGNOSTICS_SIZE))
        #expect(payload.prefix(8) == Data([1, 0, 32, 0, 0x78, 0x56, 0x34, 0x12]))
        #expect(try WireCodec.decodeRuntimeDiagnostics(payload) == diagnostics)
        payload[0] = 2
        #expect(throws: WireError(result: NXS_RESULT_UNSUPPORTED_VERSION)) { try WireCodec.decodeRuntimeDiagnostics(payload) }
        payload[0] = 1
        payload[2] = 31
        #expect(throws: WireError.self) { try WireCodec.decodeRuntimeDiagnostics(payload) }
        #expect(throws: WireError.self) { try WireCodec.decodeRuntimeDiagnostics(Data(repeating: 0, count: 31)) }
        var capabilities = DeviceCapabilities(serial: "TESTDEVICE", firmwareVersion: "test")
        capabilities.featureFlags = UInt16(NXS_FEATURE_DIAGNOSTICS)
        #expect(try WireCodec.decodeCapabilities(WireCodec.encodeCapabilities(capabilities)).supportsDiagnostics)
    }

    @Test func diagnosticRequestsRequireMinorOneAndEchoTheRevision() throws {
        let request = WireMessage(operation: .diagnostics, requestID: 17)
        #expect(request.protocolMinor == 1)
        #expect(try WireCodec.decode(WireCodec.encode(request)) == request)
        var reply = request
        reply.isResponse = true
        try reply.validateResponse(to: request)
        reply.protocolMinor = 0
        #expect(throws: WireError.self) { try reply.validateResponse(to: request) }
        let legacy = WireMessage(operation: .diagnostics, requestID: 18, protocolMinor: 0)
        #expect(throws: WireError(result: NXS_RESULT_UNSUPPORTED_VERSION)) { try WireCodec.encode(legacy) }
    }

    @Test func setNameOperationRoundTripsThroughTheWireMessage() throws {
        let request = try WireMessage(
            operation: .setName,
            requestID: 9,
            generation: 2,
            payload: WireCodec.encodeDeviceName("Office SoundBox")
        )
        #expect(try WireCodec.decode(WireCodec.encode(request)) == request)
    }

    @Test func ownerMetadataRoundTripKeepsEveryField() throws {
        let metadata = OwnerMetadata(
            date: CalendarDay(year: 2026, month: 10, day: 24),
            serialNumber: 1,
            owner: "Jürgen Österreicher",
            note: "Built in Bregenz.\nSecond line."
        )
        let block = try WireCodec.encodeOwnerMetadata(metadata)
        #expect(block.count == Int(NXS_METADATA_SIZE))
        #expect(block.prefix(8) == Data([0xA0, 0x28, 0x35, 0x01, 1, 0, 0, UInt8(NXS_METADATA_FLAG_SERIAL_NUMBER)]))
        #expect(try WireCodec.decodeOwnerMetadata(block) == metadata)
        #expect(try WireCodec.decodeOwnerMetadata(WireCodec.encodeOwnerMetadata(OwnerMetadata())) == OwnerMetadata())
    }

    @Test func ownerMetadataTextMayFillItsWholeField() throws {
        let metadata = OwnerMetadata(
            serialNumber: UInt32(NXS_SERIAL_NUMBER_MAX),
            owner: String(repeating: "o", count: Int(NXS_OWNER_NAME_LENGTH)),
            note: String(repeating: "n", count: Int(NXS_OWNER_NOTE_LENGTH))
        )
        #expect(try WireCodec.decodeOwnerMetadata(WireCodec.encodeOwnerMetadata(metadata)) == metadata)
    }

    /// 0 is a number the owner gives, NXSB0000, so it travels with the flag that tells it from no number.
    @Test func serialNumberZeroIsANumber() throws {
        let block = try WireCodec.encodeOwnerMetadata(OwnerMetadata(serialNumber: 0))
        #expect(block[4 ..< 8] == Data([0, 0, 0, UInt8(NXS_METADATA_FLAG_SERIAL_NUMBER)]))
        #expect(try WireCodec.decodeOwnerMetadata(block).serialNumber == 0)
        #expect(try WireCodec.decodeOwnerMetadata(WireCodec.encodeOwnerMetadata(OwnerMetadata())).serialNumber == nil)
    }

    @Test(arguments: [
        OwnerMetadata(owner: String(repeating: "o", count: Int(NXS_OWNER_NAME_LENGTH) + 1)),
        OwnerMetadata(owner: "Line\nfeed"),
        OwnerMetadata(note: "Tab\t"),
        OwnerMetadata(note: String(repeating: "n", count: Int(NXS_OWNER_NOTE_LENGTH) - 1) + "ä"),
        OwnerMetadata(serialNumber: UInt32(NXS_SERIAL_NUMBER_MAX) + 1),
        OwnerMetadata(date: CalendarDay(year: 2026, month: 2, day: 30)),
        OwnerMetadata(date: CalendarDay(year: 2026, month: 13, day: 1)),
        OwnerMetadata(date: CalendarDay(year: 10000, month: 1, day: 1)),
    ])
    func ownerMetadataRejectsWhatTheBoardRefuses(_ metadata: OwnerMetadata) {
        #expect(throws: WireError.self) { try WireCodec.encodeOwnerMetadata(metadata) }
    }

    @Test func metadataTravelsInTwoParts() throws {
        let metadata = OwnerMetadata(serialNumber: 42, owner: "Bench owner", note: "Note")
        let payloads = try WireCodec.metadataWritePayloads(metadata)
        #expect(payloads.count == WireCodec.metadataPartCount)
        #expect(payloads.allSatisfy { $0.count == Int(NXS_METADATA_WRITE_SIZE) })
        #expect(payloads[0].prefix(4) == Data([0, 0, 0, 0]) && payloads[1].prefix(4) == Data([1, 0, 0, 0]))
        #expect(try WireCodec.decodeOwnerMetadata(payloads[0].dropFirst(4) + payloads[1].dropFirst(4)) == metadata)
        #expect(WireCodec.metadataReadPayload(part: 1) == Data([1]))
        for payload in payloads {
            let request = WireMessage(operation: .writeMetadata, requestID: 3, generation: 2, payload: payload)
            #expect(try WireCodec.decode(WireCodec.encode(request)) == request)
        }
        let legacy = WireMessage(operation: .readMetadata, requestID: 4, payload: Data([0]), protocolMinor: 0)
        #expect(throws: WireError(result: NXS_RESULT_UNSUPPORTED_VERSION)) { try WireCodec.encode(legacy) }
    }

    @Test func capabilitiesReportMetadataSupport() throws {
        var capabilities = DeviceCapabilities(serial: "TESTDEVICE", firmwareVersion: "0.2.0")
        capabilities.flashSizeBytes = 4 * 1024 * 1024
        capabilities.featureFlags = UInt16(NXS_FEATURE_PERSISTENCE | NXS_FEATURE_FLASH_VERIFIED | NXS_FEATURE_METADATA)
        let decoded = try WireCodec.decodeCapabilities(WireCodec.encodeCapabilities(capabilities))
        #expect(decoded.supportsMetadata && decoded == capabilities)
    }

    @Test func acknowledgementsRequireMatchingRequestAndOperation() throws {
        let request = WireMessage(operation: .applyState, requestID: 7, generation: 3)
        var reply = request
        #expect(throws: WireError.self) { try reply.validateResponse(to: request) }
        reply.isResponse = true
        reply.generation = 4
        try reply.validateResponse(to: request)
        reply.requestID = 8
        #expect(throws: WireError.self) { try reply.validateResponse(to: request) }
        reply.requestID = request.requestID
        reply.operation = .persistState
        #expect(throws: WireError.self) { try reply.validateResponse(to: request) }
        reply.operation = request.operation
        reply.resultCode = NXS_RESULT_STALE_GENERATION.rawValue
        #expect(throws: WireError(result: NXS_RESULT_STALE_GENERATION)) { try reply.validateResponse(to: request) }
    }
}
