import Foundation
import NeXTsoundCore

extension DSPSettings {
    /// How loud the output is next to full scale, a perceptual anchor beside the decibels, because -24 dB on its own
    /// says little before the scale is learned.
    var shareOfFullVolumeText: String {
        let amplitudePercent = pow(10, attenuationDb / 20) * 100
        return String(localized: "\(amplitudePercent.formatted(.number.precision(.fractionLength(0 ... 1)))) % of full volume")
    }

    /// The band at `index` as a new profile has it, which resetting a band restores.
    static func defaultBand(at index: Int) -> EQBand {
        DSPSettings().bands[index]
    }
}

extension SoundProfile {
    /// Why the profile cannot go to a SoundBox as it stands, or nil when it can.
    var validationProblem: String? {
        do {
            try validate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The name the profile shows under, which is Untitled for a profile without one.
    var displayName: String {
        name.isEmpty ? String(localized: "Untitled") : name
    }
}

extension BoardConnectionState {
    /// The state in a few words, as the front panel's status column names it and VoiceOver reads the Library panel's
    /// CONNECTED LED.
    var title: String {
        switch self {
        case .disconnected: String(localized: "SoundBox not connected")
        case .detected: String(localized: "Checking SoundBox…")
        case .verified: String(localized: "SoundBox connected")
        case .mismatched: String(localized: "SoundBox not verified")
        }
    }

    /// The verified board's capabilities, or nil while no board is verified.
    var verifiedCapabilities: DeviceCapabilities? {
        guard case let .verified(capabilities) = self else {
            return nil
        }
        return capabilities
    }
}
