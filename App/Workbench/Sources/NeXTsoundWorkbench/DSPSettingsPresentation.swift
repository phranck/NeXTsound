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
