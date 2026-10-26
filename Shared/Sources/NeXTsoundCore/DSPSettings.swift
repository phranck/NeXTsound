import Foundation
import NeXTsoundProtocol

public enum DSPParameter: CaseIterable, Hashable, Sendable {
    case highPassFrequency
    case bandFrequency
    case bandGain
    case bandQuality
    case attenuation
    case limiterThreshold
    case limiterRelease

    public var bounds: ClosedRange<Float> {
        let range = nxs_parameter_range(protocolValue)
        return range.minimum ... range.maximum
    }
}

extension DSPParameter {
    var protocolValue: nxs_parameter_t {
        switch self {
        case .highPassFrequency: NXS_PARAMETER_HIGH_PASS_HZ
        case .bandFrequency: NXS_PARAMETER_EQ_HZ
        case .bandGain: NXS_PARAMETER_EQ_GAIN_DB
        case .bandQuality: NXS_PARAMETER_EQ_QUALITY
        case .attenuation: NXS_PARAMETER_ATTENUATION_DB
        case .limiterThreshold: NXS_PARAMETER_LIMITER_THRESHOLD_DB
        case .limiterRelease: NXS_PARAMETER_LIMITER_RELEASE_MS
        }
    }
}

public struct EQBand: Codable, Equatable, Sendable {
    public var frequencyHz: Float
    public var gainDb: Float
    public var quality: Float
    public var isEnabled: Bool

    public init(frequencyHz: Float, gainDb: Float = 0, quality: Float = 1, isEnabled: Bool = true) {
        self.frequencyHz = frequencyHz
        self.gainDb = gainDb
        self.quality = quality
        self.isEnabled = isEnabled
    }
}

public struct DSPSettings: Codable, Equatable, Sendable {
    public static let bandCount = Int(NXS_EQ_BAND_COUNT)

    public var highPassEnabled: Bool
    public var highPassHz: Float
    public var attenuationDb: Float
    public var limiterThresholdDb: Float
    public var limiterReleaseMs: Float
    public var isMuted: Bool
    public var bands: [EQBand]

    public init() {
        self.init(protocolSnapshot: nxs_default_snapshot())
    }

    init(protocolSnapshot snapshot: nxs_snapshot_t) {
        highPassEnabled = snapshot.high_pass_enabled != 0
        highPassHz = snapshot.high_pass_hz
        attenuationDb = snapshot.attenuation_db
        limiterThresholdDb = snapshot.limiter_threshold_db
        limiterReleaseMs = snapshot.limiter_release_ms
        isMuted = snapshot.muted != 0
        bands = withUnsafeBytes(of: snapshot.bands) { bytes in
            bytes.bindMemory(to: nxs_eq_band_t.self).map { band in
                EQBand(frequencyHz: band.frequency_hz, gainDb: band.gain_db, quality: band.quality, isEnabled: band.enabled != 0)
            }
        }
    }
}

public extension DSPSettings {
    func validate() throws {
        let snapshot = try protocolSnapshot(profileID: UUID(), revision: 0)
        let isValid = withUnsafePointer(to: snapshot) { nxs_snapshot_is_valid($0) }
        guard isValid else {
            throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
        }
    }

    /// These settings with every value moved into the range `ranges` gives for its parameter, and a value without a range
    /// left as it is. A board reports the ranges it takes in its capabilities, and older firmware reports narrower ones,
    /// such as Master Volume up to 0 dB, so a write limited this way never asks a board for more than it takes.
    func limited(to ranges: [DSPParameter: ClosedRange<Float>]) -> DSPSettings {
        func limit(_ value: Float, to parameter: DSPParameter) -> Float {
            guard let range = ranges[parameter] else {
                return value
            }
            return min(max(value, range.lowerBound), range.upperBound)
        }
        var limited = self
        limited.highPassHz = limit(highPassHz, to: .highPassFrequency)
        limited.attenuationDb = limit(attenuationDb, to: .attenuation)
        limited.limiterThresholdDb = limit(limiterThresholdDb, to: .limiterThreshold)
        limited.limiterReleaseMs = limit(limiterReleaseMs, to: .limiterRelease)
        limited.bands = bands.map { band in
            var limitedBand = band
            limitedBand.frequencyHz = limit(band.frequencyHz, to: .bandFrequency)
            limitedBand.gainDb = limit(band.gainDb, to: .bandGain)
            limitedBand.quality = limit(band.quality, to: .bandQuality)
            return limitedBand
        }
        return limited
    }
}

extension DSPSettings {
    func protocolSnapshot(profileID: UUID, revision: UInt32) throws -> nxs_snapshot_t {
        guard bands.count == Self.bandCount else {
            throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
        }
        var snapshot = nxs_default_snapshot()
        snapshot.profile_revision = revision
        snapshot.high_pass_enabled = highPassEnabled ? 1 : 0
        snapshot.high_pass_hz = highPassHz
        snapshot.attenuation_db = attenuationDb
        snapshot.limiter_threshold_db = limiterThresholdDb
        snapshot.limiter_release_ms = limiterReleaseMs
        snapshot.muted = isMuted ? 1 : 0
        withUnsafeBytes(of: profileID.uuid) { identifier in
            withUnsafeMutableBytes(of: &snapshot.profile_id) { destination in
                destination.copyBytes(from: identifier)
            }
        }
        withUnsafeMutableBytes(of: &snapshot.bands) { bytes in
            let destination = bytes.bindMemory(to: nxs_eq_band_t.self)
            for (index, band) in bands.enumerated() {
                destination[index] = nxs_eq_band_t(
                    frequency_hz: band.frequencyHz,
                    gain_db: band.gainDb,
                    quality: band.quality,
                    enabled: band.isEnabled ? 1 : 0
                )
            }
        }
        return snapshot
    }
}
