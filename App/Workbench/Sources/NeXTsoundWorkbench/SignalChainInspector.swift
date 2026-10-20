import Foundation
import NeXTsoundCore
import SwiftUI

struct SignalChainInspector: View {
    @Binding var settings: DSPSettings

    var body: some View {
        VStack(spacing: 18) {
            HighPassControls(settings: $settings)
            OutputControls(settings: $settings)
            LimiterControls(settings: $settings)
        }
    }
}

private struct HighPassControls: View {
    @Binding var settings: DSPSettings

    var body: some View {
        GroupBox("High-pass") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enabled", isOn: $settings.highPassEnabled)
                ParameterControl(title: "Cutoff", parameter: .highPassFrequency, unit: "Hz", value: $settings.highPassHz, logarithmic: true)
                    .disabled(!settings.highPassEnabled)
            }
            .padding(10)
        }
    }
}

private struct OutputControls: View {
    @Binding var settings: DSPSettings

    var body: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Muted", isOn: $settings.isMuted)
                ParameterControl(title: "Master Volume", parameter: .attenuation, unit: "dB", value: $settings.attenuationDb)
                Text(attenuationPercentText)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }
}

private extension OutputControls {
    /// A perceptual anchor alongside the dB value: how loud the signal is relative to full
    /// scale, since -24 dB on its own does not say much before you have learned the scale.
    var attenuationPercentText: String {
        let amplitudePercent = pow(10, settings.attenuationDb / 20) * 100
        return String(localized: "\(amplitudePercent.formatted(.number.precision(.fractionLength(0 ... 1)))) % of full volume")
    }
}

private struct LimiterControls: View {
    @Binding var settings: DSPSettings

    var body: some View {
        GroupBox("Sample-peak limiter") {
            VStack(alignment: .leading, spacing: 12) {
                ParameterControl(title: "Ceiling", parameter: .limiterThreshold, unit: "dB", value: $settings.limiterThresholdDb)
                ParameterControl(
                    title: "Release",
                    parameter: .limiterRelease,
                    unit: "ms",
                    value: $settings.limiterReleaseMs,
                    logarithmic: true
                )
            }
            .padding(10)
        }
    }
}
