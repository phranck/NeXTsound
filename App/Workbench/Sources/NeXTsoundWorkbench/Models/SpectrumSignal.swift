import Foundation
import NeXTsoundCore

/// The signal the SoundBox sends to its amplifier, rebuilt from the stream macOS sends it, in the firmware's order: the
/// host's volume, then the board's DSP with the selected profile's settings, then the host's mute.
///
/// The DSP is the firmware's own engine, so the spectrum shows what the high-pass, the EQ, the attenuation and the
/// limiter make of the audio. A profile edit waits for a running crossfade to end and is offered again with the next
/// cycle, as the firmware's audio owner offers it with the next block. Settings the engine refuses are dropped, and the
/// signal keeps the settings it has.
struct SpectrumSignal {
    private var engine: DSPEngine
    /// The settings last offered to the engine, applied or still waiting for a crossfade to end.
    private var settings: DSPSettings
    private var isSettingsPending = false
    private var scaled: [Float] = []

    /// - Parameter inputs: The settings the engine crossfades into from silence, as the board does when it starts.
    /// - Throws: `WireError` for settings outside the protocol's bounds.
    init(inputs: SpectrumInputs.Values) throws {
        engine = try DSPEngine(settings: inputs.settings)
        settings = inputs.settings
    }
}

extension SpectrumSignal {
    /// Turns one cycle of `stereo`, interleaved left and right samples, into the mono signal for the amplifier in
    /// `mono`, with the `inputs` of this cycle. `mono` keeps its storage.
    mutating func process(_ stereo: [Float], inputs: SpectrumInputs.Values, into mono: inout [Float]) {
        offer(inputs.settings)
        let hostGain = Float(pow(10, Double(inputs.hostVolumeDb) / 20))
        scaled.removeAll(keepingCapacity: true)
        scaled.append(contentsOf: stereo.lazy.map { $0 * hostGain })
        if !engine.process(scaled, into: &mono) || inputs.hostIsMuted {
            for index in mono.indices {
                mono[index] = 0
            }
        }
    }
}

private extension SpectrumSignal {
    /// Hands new settings to the engine, or tries again with settings a running crossfade kept waiting.
    mutating func offer(_ newSettings: DSPSettings) {
        if newSettings != settings {
            settings = newSettings
            isSettingsPending = true
        }
        guard isSettingsPending else {
            return
        }
        do {
            isSettingsPending = try !engine.apply(settings)
        } catch {
            isSettingsPending = false
        }
    }
}
