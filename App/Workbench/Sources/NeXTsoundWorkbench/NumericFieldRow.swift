import SwiftUI

/// A labeled numeric text field row, extracted from `ParameterControl`'s original layout so a
/// non-slider optional value (nil meaning "unknown") can share the same visual shape as the DSP
/// sliders.
struct NumericFieldRow: View {
    let title: String
    let unit: String
    @Binding var value: Double?
    var fractionDigits: ClosedRange<Int> = 0 ... 2

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            TextField(title, value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 90)
                .accessibilityLabel(title)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}
