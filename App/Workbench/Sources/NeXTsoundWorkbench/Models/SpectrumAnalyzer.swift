import Accelerate
import Foundation

/// Measures the level of every `SpectrumBand` in a stream of mono samples, as a real-time analyzer does.
///
/// It keeps the last `transformLength` samples, and after every `1 / updatesPerSecond` seconds of audio it weights them
/// with a Hann window, transforms them and sums the power of each band's bins. A band rises to a louder measurement at
/// once and falls toward a quieter one at `fallDecibelsPerSecond`, so the bars move as a hardware analyzer's do.
///
/// At 48 kHz the transform's bins lie 5.9 Hz apart, which is wider than the lowest bands. Such a band takes its width's
/// share of the nearest bin's power, so a low tone also lights the bands beside it.
///
/// An analyzer is not thread-safe: the audio queue that feeds it owns it, and it allocates nothing after `init`.
final class SpectrumAnalyzer {
    /// The samples each transform covers, 171 ms at 48 kHz.
    static let transformLength = 8192
    /// How often the analyzer measures the bands, counted in seconds of audio.
    static let updatesPerSecond = 30.0
    /// How fast a band's level falls toward a quieter measurement.
    static let fallDecibelsPerSecond: Float = 40
    /// The level of a band without power, far below anything the display shows.
    static let floorDecibels: Float = -120

    private let transform: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    /// The factor that turns a band's summed bin power into its share of a full-scale sine's power.
    private let powerScale: Float
    private let measures: [BandMeasure]
    private let hopLength: Int
    private let hopSeconds: Double
    /// The last `transformLength` samples, the oldest at `historyIndex`.
    private var history: [Float]
    private var historyIndex = 0
    private var samplesUntilUpdate: Int
    private var weighted: [Float]
    private let silentImaginary: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var levels: [Float]

    /// - Parameter sampleRate: The rate of the samples `append(_:)` receives, in hertz.
    /// - Throws: `SpectrumError.invalidSampleRate` for a rate that is not finite or too low for one update per
    ///   `updatesPerSecond`.
    init(sampleRate: Double) throws {
        let hopLength = sampleRate.isFinite ? Int((sampleRate / Self.updatesPerSecond).rounded()) : 0
        guard hopLength > 0 else {
            throw SpectrumError.invalidSampleRate
        }
        let length = Self.transformLength
        transform = try vDSP.DiscreteFourierTransform(
            count: length,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: length, isHalfWindow: false)
        // A sine of amplitude A puts N·A²/4 times the window's energy into its positive-frequency bins, so this factor
        // reads a full-scale sine as 1, which is 0 dB.
        powerScale = 4 / (Float(length) * vDSP.sumOfSquares(window))
        measures = Self.measures(sampleRate: sampleRate)
        self.hopLength = hopLength
        hopSeconds = Double(hopLength) / sampleRate
        history = Array(repeating: 0, count: length)
        samplesUntilUpdate = hopLength
        weighted = Array(repeating: 0, count: length)
        silentImaginary = Array(repeating: 0, count: length)
        real = Array(repeating: 0, count: length)
        imaginary = Array(repeating: 0, count: length)
        levels = SpectrumLevels.silent.decibels
    }
}

extension SpectrumAnalyzer {
    /// Adds `samples` to the analyzed stream and returns the bands' levels after the last update they completed, or
    /// nil when they completed none.
    func append(_ samples: some Collection<Float>) -> SpectrumLevels? {
        var updated = false
        for sample in samples {
            history[historyIndex] = sample
            historyIndex = historyIndex + 1 == Self.transformLength ? 0 : historyIndex + 1
            samplesUntilUpdate -= 1
            if samplesUntilUpdate == 0 {
                measureBands()
                samplesUntilUpdate = hopLength
                updated = true
            }
        }
        return updated ? SpectrumLevels(decibels: levels) : nil
    }

    /// A band's level `seconds` after it stood at `current`, with a new measurement of `measured`: the measurement when
    /// it is louder, and otherwise the level fallen at `fallDecibelsPerSecond`, but never below the measurement.
    static func level(from current: Float, toward measured: Float, after seconds: Double) -> Float {
        measured >= current ? measured : max(measured, current - fallDecibelsPerSecond * Float(seconds))
    }
}

private extension SpectrumAnalyzer {
    /// The transform bins a band sums, and the share of their power that belongs to the band.
    struct BandMeasure {
        let bins: ClosedRange<Int>
        let share: Float
    }

    /// The bins of every band: those whose frequencies lie between its edges with their whole power, or, for a band
    /// narrower than a bin, the nearest bin with the share the band's width takes of it.
    static func measures(sampleRate: Double) -> [BandMeasure] {
        let binWidth = sampleRate / Double(transformLength)
        let highestBin = transformLength / 2
        return SpectrumBand.all.map { spectrumBand in
            let first = Int((spectrumBand.lowerHz / binWidth).rounded(.up))
            let last = min(Int((spectrumBand.upperHz / binWidth).rounded(.up)) - 1, highestBin)
            if first <= last {
                return BandMeasure(bins: first ... last, share: 1)
            }
            let nearest = min(Int((spectrumBand.centerHz / binWidth).rounded()), highestBin)
            return BandMeasure(bins: nearest ... nearest, share: Float((spectrumBand.upperHz - spectrumBand.lowerHz) / binWidth))
        }
    }

    /// Transforms the windowed history, oldest sample first, and moves every band's level toward its measurement.
    func measureBands() {
        let length = Self.transformLength
        for offset in 0 ..< length {
            let index = historyIndex + offset
            weighted[offset] = history[index < length ? index : index - length] * window[offset]
        }
        transform.transform(inputReal: weighted, inputImaginary: silentImaginary, outputReal: &real, outputImaginary: &imaginary)
        for (index, measure) in measures.enumerated() {
            var power: Float = 0
            for bin in measure.bins {
                power += real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
            }
            let measured = max(10 * log10(power * measure.share * powerScale), Self.floorDecibels)
            levels[index] = Self.level(from: levels[index], toward: measured, after: hopSeconds)
        }
    }
}
