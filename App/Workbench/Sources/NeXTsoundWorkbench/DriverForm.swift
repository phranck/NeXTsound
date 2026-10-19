import NeXTsoundCore
import SwiftUI

struct DriverForm: View {
    @Binding var draft: DriverRecord
    let validationError: String?
    let onApply: () -> Void
    @State private var sourceURLText: String

    init(draft: Binding<DriverRecord>, validationError: String?, onApply: @escaping () -> Void) {
        _draft = draft
        self.validationError = validationError
        self.onApply = onApply
        _sourceURLText = State(initialValue: draft.wrappedValue.sourceURLs.map(\.absoluteString).joined(separator: "\n"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IdentityGroup(draft: $draft, sourceURLText: $sourceURLText)
                ElectricalGroup(draft: $draft)
                ThieleSmallGroup(draft: $draft)
                MechanicalGroup(draft: $draft)
                MountingGroup(draft: $draft)
                PowerGroup(draft: $draft)
                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Apply", action: apply)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
        }
    }
}

private extension DriverForm {
    func apply() {
        draft.sourceURLs = sourceURLText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
        onApply()
    }
}

private struct IdentityGroup: View {
    @Binding var draft: DriverRecord
    @Binding var sourceURLText: String

    var body: some View {
        GroupBox("Identity") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                TextField("Manufacturer", text: manufacturerBinding)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: modelBinding)
                    .textFieldStyle(.roundedBorder)
                Picker("Origin", selection: $draft.origin) {
                    ForEach(SpecificationOrigin.allCases, id: \.self) { origin in
                        Text(origin.displayName).tag(origin)
                    }
                }
                Text("Source URLs, one per line")
                    .foregroundStyle(.secondary)
                TextEditor(text: $sourceURLText)
                    .frame(height: 60)
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3 ... 6)
            }
            .padding(10)
        }
    }
}

private extension IdentityGroup {
    var manufacturerBinding: Binding<String> {
        Binding(get: { draft.manufacturer ?? "" }, set: { draft.manufacturer = $0.isEmpty ? nil : $0 })
    }

    var modelBinding: Binding<String> {
        Binding(get: { draft.model ?? "" }, set: { draft.model = $0.isEmpty ? nil : $0 })
    }
}

private struct ElectricalGroup: View {
    @Binding var draft: DriverRecord

    var body: some View {
        GroupBox("Electrical") {
            VStack(alignment: .leading, spacing: 12) {
                NumericFieldRow(title: "Nominal impedance", unit: "Ω", value: $draft.nominalImpedanceOhms)
                NumericFieldRow(title: "Re", unit: "Ω", value: $draft.reOhms)
                NumericFieldRow(title: "Le", unit: "mH", value: $draft.leMillihenries, fractionDigits: 0 ... 3)
                NumericFieldRow(title: "Bl", unit: "T·m", value: $draft.blTeslaMeters, fractionDigits: 0 ... 3)
            }
            .padding(10)
        }
    }
}

private struct ThieleSmallGroup: View {
    @Binding var draft: DriverRecord

    var body: some View {
        GroupBox("Thiele/Small") {
            VStack(alignment: .leading, spacing: 12) {
                NumericFieldRow(title: "Fs", unit: "Hz", value: $draft.fsHz)
                NumericFieldRow(title: "Qts", unit: "", value: $draft.qts, fractionDigits: 0 ... 3)
                NumericFieldRow(title: "Qes", unit: "", value: $draft.qes, fractionDigits: 0 ... 3)
                NumericFieldRow(title: "Qms", unit: "", value: $draft.qms, fractionDigits: 0 ... 3)
                NumericFieldRow(title: "Vas", unit: "L", value: $draft.vasLiters, fractionDigits: 0 ... 3)
            }
            .padding(10)
        }
    }
}

private struct MechanicalGroup: View {
    @Binding var draft: DriverRecord

    var body: some View {
        GroupBox("Mechanical") {
            VStack(alignment: .leading, spacing: 12) {
                NumericFieldRow(title: "Sd", unit: "cm²", value: $draft.sdSquareCentimeters)
                NumericFieldRow(title: "Mms", unit: "g", value: $draft.mmsGrams)
                NumericFieldRow(title: "Xmax", unit: "mm", value: $draft.xmaxMillimeters)
            }
            .padding(10)
        }
    }
}

private struct MountingGroup: View {
    @Binding var draft: DriverRecord

    var body: some View {
        GroupBox("Mounting and fit") {
            VStack(alignment: .leading, spacing: 12) {
                NumericFieldRow(title: "Frame diameter", unit: "mm", value: $draft.frameDiameterMillimeters)
                NumericFieldRow(title: "Mounting pitch circle", unit: "mm", value: $draft.mountingPitchCircleDiameterMillimeters)
                NumericFieldRow(title: "Mounting holes", unit: "", value: mountingHoleCountBinding, fractionDigits: 0 ... 0)
                NumericFieldRow(title: "Mounting hole diameter", unit: "mm", value: $draft.mountingHoleDiameterMillimeters)
                NumericFieldRow(title: "Rear depth", unit: "mm", value: $draft.rearDepthMillimeters)
                NumericFieldRow(title: "Front protrusion", unit: "mm", value: $draft.frontProtrusionMillimeters)
            }
            .padding(10)
        }
    }
}

private extension MountingGroup {
    var mountingHoleCountBinding: Binding<Double?> {
        Binding(get: { draft.mountingHoleCount.map(Double.init) }, set: { draft.mountingHoleCount = $0.map { Int($0.rounded()) } })
    }
}

private struct PowerGroup: View {
    @Binding var draft: DriverRecord

    var body: some View {
        GroupBox("Power") {
            VStack(alignment: .leading, spacing: 12) {
                NumericFieldRow(title: "Rated power", unit: "W", value: $draft.ratedPowerWatts)
                NumericFieldRow(title: "Recommended high-pass", unit: "Hz", value: $draft.recommendedHighPassHz)
            }
            .padding(10)
        }
    }
}

private extension SpecificationOrigin {
    var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .userProvided: "User provided"
        case .datasheet: "Datasheet"
        }
    }
}
