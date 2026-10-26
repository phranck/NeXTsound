import Foundation
import NeXTsoundCore

extension DSPSettings {
    /// How loud the output is next to full scale, a perceptual anchor beside the decibels, because a value in decibels
    /// on its own says little before the scale is learned. Above 0 dB the limiter holds every peak at its ceiling, so
    /// the text says that instead of a share above 100 %.
    var shareOfFullVolumeText: String {
        guard attenuationDb <= 0 else {
            return String(
                localized: "above full volume, the limiter holds the peaks",
                comment: "What VoiceOver reads after the Master Volume when it raises the level above full volume."
            )
        }
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

extension DriverRecord {
    /// The name the driver model shows under, which is Untitled for one without a name.
    var displayName: String {
        name.isEmpty ? String(localized: "Untitled") : name
    }

    /// The driver model's datasheet, which is its first source.
    var datasheetURL: URL? {
        sourceURLs.first
    }

    /// The sources one per line, as the driver form shows them for editing.
    var sourceURLText: String {
        sourceURLs.map(\.absoluteString).joined(separator: "\n")
    }

    /// The manufacturer as the driver form edits it, where an empty text means none.
    var manufacturerText: String {
        get { manufacturer ?? "" }
        set { manufacturer = newValue.isEmpty ? nil : newValue }
    }

    /// The model as the driver form edits it, where an empty text means none.
    var modelText: String {
        get { model ?? "" }
        set { model = newValue.isEmpty ? nil : newValue }
    }

    /// The mounting hole count as the driver form's number field edits it, rounded to whole holes.
    var mountingHoleCountValue: Double? {
        get { mountingHoleCount.map(Double.init) }
        set { mountingHoleCount = newValue.map { Int($0.rounded()) } }
    }

    /// The sources in `text`, one per line, without blank lines and the spaces around each line. A line that
    /// `URL(string:)` cannot read is left out.
    static func sourceURLs(fromText text: String) -> [URL] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
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
