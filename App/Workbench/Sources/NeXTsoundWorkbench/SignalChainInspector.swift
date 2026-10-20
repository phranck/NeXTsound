import Foundation
import NeXTsoundCore
import SwiftUI

struct SignalChainInspector: View {
    @Binding var settings: DSPSettings
    let slotA: DSPSettings?
    let slotB: DSPSettings?
    let onCaptureA: () -> Void
    let onRecallA: () -> Void
    let onCaptureB: () -> Void
    let onRecallB: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HighPassControls(settings: $settings)
            OutputControls(settings: $settings)
            LimiterControls(settings: $settings)
            ABControls(
                slotA: slotA,
                slotB: slotB,
                onCaptureA: onCaptureA,
                onRecallA: onRecallA,
                onCaptureB: onCaptureB,
                onRecallB: onRecallB
            )
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

/// Volatile capture/recall of the current DSP settings into two comparison slots, for A/B
/// listening without replacing the profile's identity or leaving the editing session.
private struct ABControls: View {
    let slotA: DSPSettings?
    let slotB: DSPSettings?
    let onCaptureA: () -> Void
    let onRecallA: () -> Void
    let onCaptureB: () -> Void
    let onRecallB: () -> Void

    var body: some View {
        GroupBox("A/B compare") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Capture A", systemImage: "a.circle", action: onCaptureA)
                        .help("Capture the current DSP settings into slot A")
                    Button("Recall A", systemImage: "arrow.uturn.backward", action: onRecallA)
                        .disabled(slotA == nil)
                        .help("Replace the current DSP settings with slot A's capture")
                }
                HStack {
                    Button("Capture B", systemImage: "b.circle", action: onCaptureB)
                        .help("Capture the current DSP settings into slot B")
                    Button("Recall B", systemImage: "arrow.uturn.backward", action: onRecallB)
                        .disabled(slotB == nil)
                        .help("Replace the current DSP settings with slot B's capture")
                }
            }
            .padding(10)
        }
    }
}
