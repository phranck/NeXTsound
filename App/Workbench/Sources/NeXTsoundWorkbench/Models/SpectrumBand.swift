import Foundation
import NeXTsoundCore

/// One band of the live spectrum: a sixth of an octave around its center, with its edges a twelfth of an octave either
/// side of it.
///
/// The bands are fixed rather than one per dot column, so a band's level stays the same whatever width the display's
/// graph has while the status column slides. Their centers are powers of the sixth root of two from 1 kHz, so a 1 kHz
/// tone falls on the middle of a band.
struct SpectrumBand: Equatable, Sendable {
    /// The bands of the spectrum, from the lowest to the highest: every band whose edges both lie inside the EQ
    /// curve's frequency range.
    static let all: [SpectrumBand] = {
        let range = DSPParameter.bandFrequency.bounds
        let steps = Double(bandsPerOctave)
        let lowest = Int((steps * log2(Double(range.lowerBound) / referenceHz) + 0.5).rounded(.up))
        let highest = Int((steps * log2(Double(range.upperBound) / referenceHz) - 0.5).rounded(.down))
        return (lowest ... highest).map { step in
            SpectrumBand(centerHz: referenceHz * pow(2, Double(step) / steps))
        }
    }()

    /// The bands an octave holds.
    static let bandsPerOctave = 6
    /// The center the band centers count from.
    static let referenceHz = 1000.0

    let centerHz: Double
}

extension SpectrumBand {
    /// The band's lower edge, where the band below it ends.
    var lowerHz: Double {
        centerHz / Self.edgeRatio
    }

    /// The band's upper edge, where the band above it starts.
    var upperHz: Double {
        centerHz * Self.edgeRatio
    }
}

private extension SpectrumBand {
    /// The ratio between a band's center and each of its edges: half a band, a twelfth of an octave.
    static let edgeRatio = pow(2, 0.5 / Double(bandsPerOctave))
}

/// The levels of the live spectrum, one for each of `SpectrumBand.all` in the same order, in decibels below full
/// scale. A full-scale sine reads 0 dB on the band that holds it.
struct SpectrumLevels: Equatable, Sendable {
    /// The spectrum of silence: every band on the analyzer's floor.
    static let silent = SpectrumLevels(decibels: Array(repeating: SpectrumAnalyzer.floorDecibels, count: SpectrumBand.all.count))

    let decibels: [Float]
}
