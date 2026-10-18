import Foundation
import NeXTsoundCore
import SwiftUI

struct ParameterControl: View {
    let title: String
    let parameter: DSPParameter
    let unit: String
    @Binding var value: Float
    var logarithmic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                TextField(title, value: $value, format: .number.precision(.fractionLength(0 ... 2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 76)
                    .accessibilityLabel(title)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
            Group {
                if logarithmic, let scale = try? LogarithmicScale(bounds: parameter.bounds) {
                    Slider(value: scaledBinding(scale), in: 0 ... 1) { Text(title) }
                } else {
                    Slider(value: $value, in: parameter.bounds) { Text(title) }
                }
            }
            .labelsHidden()
            .accessibilityLabel(title)
            .accessibilityValue("\(value.formatted()) \(unit)")
        }
        .controlSize(.regular)
    }
}

private extension ParameterControl {
    func scaledBinding(_ scale: LogarithmicScale) -> Binding<Double> {
        Binding(get: { scale.position(for: value) }, set: { value = scale.value(at: $0) })
    }
}
