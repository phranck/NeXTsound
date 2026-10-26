import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct SpectrumSignalTests {
    /// The host's volume lowers the signal before the board's DSP, as the firmware applies it.
    @Test func theHostVolumeLowersTheSignal() throws {
        let quiet = SpectrumInputs.Values(settings: Self.flat(), hostVolumeDb: -20, hostIsMuted: false)
        var signal = try SpectrumSignal(inputs: quiet)
        #expect(abs(Self.decibels(signal.peak(inputs: quiet), against: 0.5) + 20) < 0.1)
    }

    /// The host's mute silences the signal, as it silences the speaker.
    @Test func theHostMuteSilencesTheSignal() throws {
        let muted = SpectrumInputs.Values(settings: Self.flat(), hostVolumeDb: 0, hostIsMuted: true)
        var signal = try SpectrumSignal(inputs: muted)
        #expect(signal.peak(inputs: muted) == 0)
    }

    /// An edit of the profile reaches the signal within a few blocks, once its crossfade has run.
    @Test func aProfileEditReachesTheSignal() throws {
        let loud = SpectrumInputs.Values(settings: Self.flat(), hostVolumeDb: 0, hostIsMuted: false)
        var signal = try SpectrumSignal(inputs: loud)
        _ = signal.peak(inputs: loud)
        var quieter = loud
        quieter.settings.attenuationDb = -12
        #expect(abs(Self.decibels(signal.peak(inputs: quieter), against: 0.5) + 12) < 0.1)
    }

    /// Settings the DSP refuses leave the signal on the settings it has.
    @Test func refusedSettingsLeaveTheSignalAsItIs() throws {
        let loud = SpectrumInputs.Values(settings: Self.flat(), hostVolumeDb: 0, hostIsMuted: false)
        var signal = try SpectrumSignal(inputs: loud)
        _ = signal.peak(inputs: loud)
        var invalid = loud
        invalid.settings.attenuationDb = .nan
        #expect(abs(signal.peak(inputs: invalid) - 0.5) < 0.01)
    }

    /// Before the board has reported, the signal takes the host at full volume and not muted.
    @Test func withoutAReportTheHostIsAtFullVolume() {
        var runtime = DeviceRuntimeStatus()
        runtime.hostVolumeDb = -12
        runtime.hostIsMuted = true
        let reported = SpectrumInputs.Values(settings: Self.flat(), runtime: runtime)
        let unreported = SpectrumInputs.Values(settings: Self.flat(), runtime: nil)
        #expect(reported.hostVolumeDb == -12 && reported.hostIsMuted)
        #expect(unreported.hostVolumeDb == 0 && !unreported.hostIsMuted)
    }

    /// The inputs hand the main actor's latest values to the capture's queue.
    @Test func theInputsHoldTheLatestValues() {
        let inputs = SpectrumInputs()
        var values = inputs.current
        values.hostVolumeDb = -6
        inputs.current = values
        #expect(inputs.current.hostVolumeDb == -6)
    }
}

private extension SpectrumSignalTests {
    /// A profile that leaves the signal as it is: no high-pass, flat bands, no attenuation, not muted.
    static func flat() -> DSPSettings {
        var settings = DSPSettings()
        settings.highPassEnabled = false
        settings.attenuationDb = 0
        settings.limiterThresholdDb = -1
        settings.isMuted = false
        for index in settings.bands.indices {
            settings.bands[index].gainDb = 0
        }
        return settings
    }

    static func decibels(_ amplitude: Float, against reference: Float) -> Float {
        20 * log10(amplitude / reference)
    }
}

private extension SpectrumSignal {
    /// The peak of the signal for a 1 kHz sine of half full scale on both channels, over the second half of 0.1 s, after
    /// a crossfade into new settings has run.
    mutating func peak(inputs: SpectrumInputs.Values) -> Float {
        let frames = 4800
        var stereo: [Float] = []
        for frame in 0 ..< frames {
            let sample = 0.5 * Float(sin(2 * Double.pi * 1000 * Double(frame) / 48000))
            stereo += [sample, sample]
        }
        var mono: [Float] = []
        process(stereo, inputs: inputs, into: &mono)
        return mono[(frames / 2)...].map(abs).max() ?? 0
    }
}
