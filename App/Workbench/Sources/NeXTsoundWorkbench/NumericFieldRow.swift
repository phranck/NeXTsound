import SwiftUI

/// A labeled numeric text field for an optional value, where nil means unknown, with the value's unit beside it.
struct NumericFieldRow: View {
    let title: LocalizedStringKey
    let unit: String
    @Binding var value: Double?
    var fractionDigits: ClosedRange<Int> = 0 ... 2

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 190, alignment: .leading)
            TextField(title, value: $value, format: .number.precision(.fractionLength(fractionDigits)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 90)
                .accessibilityLabel(title)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}
