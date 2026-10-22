import Foundation
import NeXTsoundCore
import SwiftUI

struct ParameterControl: View {
    let title: LocalizedStringKey
    let parameter: DSPParameter
    let unit: String
    @Binding var value: Float

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
                if parameter.usesLogarithmicScale {
                    Slider(value: positionBinding, in: 0 ... 1) { Text(title) }
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
    /// The slider's position on the parameter's logarithmic scale, mapped back to the value as it moves.
    var positionBinding: Binding<Double> {
        let scale = FaderScale(parameter: parameter)
        return Binding(get: { scale.position(for: value) }, set: { value = scale.value(at: $0) })
    }
}
