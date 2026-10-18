import NeXTsoundCore
import SwiftUI

struct BandEditor: View {
    @Binding var bands: [EQBand]
    @State private var selectedBand = 2

    var body: some View {
        GroupBox("Equalizer") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Band", selection: $selectedBand) {
                    ForEach(0 ..< DSPSettings.bandCount, id: \.self) { index in
                        Text("Band \(index + 1)").tag(index)
                    }
                }
                .pickerStyle(.segmented)
                if bands.indices.contains(selectedBand) {
                    EQBandControls(band: $bands[selectedBand])
                    Button("Reset band", systemImage: "arrow.counterclockwise") {
                        bands[selectedBand] = DSPSettings().bands[selectedBand]
                    }
                    .controlSize(.regular)
                }
            }
            .padding(10)
        }
    }
}

private struct EQBandControls: View {
    @Binding var band: EQBand

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Band enabled", isOn: $band.isEnabled)
            VStack(spacing: 12) {
                ParameterControl(title: "Frequency", parameter: .bandFrequency, unit: "Hz", value: $band.frequencyHz, logarithmic: true)
                ParameterControl(title: "Gain", parameter: .bandGain, unit: "dB", value: $band.gainDb)
                ParameterControl(title: "Quality", parameter: .bandQuality, unit: "Q", value: $band.quality, logarithmic: true)
            }
            .disabled(!band.isEnabled)
        }
    }
}
