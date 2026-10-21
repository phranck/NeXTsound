import NeXTsoundCore
import SwiftUI

struct DriverForm: View {
    @Binding var draft: DriverRecord
    let validationError: String?
    let onApply: () -> Void
    @State private var sourceURLText: String
    private var sections = SectionExpansionState()

    init(draft: Binding<DriverRecord>, validationError: String?, onApply: @escaping () -> Void) {
        _draft = draft
        self.validationError = validationError
        self.onApply = onApply
        _sourceURLText = State(initialValue: draft.wrappedValue.sourceURLs.map(\.absoluteString).joined(separator: "\n"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(draft.name.isEmpty ? String(localized: "Untitled") : draft.name)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                DriverPreviewHeader(draft: draft)
                HStack {
                    AddImageButton(draft: $draft)
                    ExpandAllToggle(sections: sections)
                }
                CollapsibleSection(title: "Identity", systemImage: "tag", isExpanded: sections.identityBinding) {
                    IdentityGroup(draft: $draft, sourceURLText: $sourceURLText)
                }
                CollapsibleSection(title: "Electrical", systemImage: "bolt.fill", isExpanded: sections.electricalBinding) {
                    ElectricalGroup(draft: $draft)
                }
                CollapsibleSection(title: "Thiele/Small", systemImage: "waveform", isExpanded: sections.thieleSmallBinding) {
                    ThieleSmallGroup(draft: $draft)
                }
                CollapsibleSection(title: "Mechanical", systemImage: "gearshape.fill", isExpanded: sections.mechanicalBinding) {
                    MechanicalGroup(draft: $draft)
                }
                CollapsibleSection(title: "Mounting and fit", systemImage: "ruler.fill", isExpanded: sections.mountingBinding) {
                    MountingGroup(draft: $draft)
                }
                CollapsibleSection(title: "Power", systemImage: "powerplug.fill", isExpanded: sections.powerBinding) {
                    PowerGroup(draft: $draft)
                }
            }
            .padding(22)
            .padding(.bottom, 60)
        }
        .fontDesign(.monospaced)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ApplyBar(driverID: draft.id, validationError: validationError, onApply: apply)
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
        VStack(alignment: .leading, spacing: 12) {
            NumericFieldRow(title: "Nominal impedance", unit: "Ω", value: $draft.nominalImpedanceOhms)
            NumericFieldRow(title: "Re", unit: "Ω", value: $draft.reOhms)
            NumericFieldRow(title: "Le", unit: "mH", value: $draft.leMillihenries, fractionDigits: 0 ... 3)
            NumericFieldRow(title: "Bl", unit: "T·m", value: $draft.blTeslaMeters, fractionDigits: 0 ... 3)
        }
    }
}

private struct ThieleSmallGroup: View {
    @Binding var draft: DriverRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NumericFieldRow(title: "Fs", unit: "Hz", value: $draft.fsHz)
            NumericFieldRow(title: "Qts", unit: "", value: $draft.qts, fractionDigits: 0 ... 3)
            NumericFieldRow(title: "Qes", unit: "", value: $draft.qes, fractionDigits: 0 ... 3)
            NumericFieldRow(title: "Qms", unit: "", value: $draft.qms, fractionDigits: 0 ... 3)
            NumericFieldRow(title: "Vas", unit: "L", value: $draft.vasLiters, fractionDigits: 0 ... 3)
        }
    }
}

private struct MechanicalGroup: View {
    @Binding var draft: DriverRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NumericFieldRow(title: "Sd", unit: "cm²", value: $draft.sdSquareCentimeters)
            NumericFieldRow(title: "Mms", unit: "g", value: $draft.mmsGrams)
            NumericFieldRow(title: "Xmax", unit: "mm", value: $draft.xmaxMillimeters)
        }
    }
}

private struct MountingGroup: View {
    @Binding var draft: DriverRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NumericFieldRow(title: "Frame diameter", unit: "mm", value: $draft.frameDiameterMillimeters)
            NumericFieldRow(title: "Mounting pitch circle", unit: "mm", value: $draft.mountingPitchCircleDiameterMillimeters)
            NumericFieldRow(title: "Mounting holes", unit: "", value: mountingHoleCountBinding, fractionDigits: 0 ... 0)
            NumericFieldRow(title: "Mounting hole diameter", unit: "mm", value: $draft.mountingHoleDiameterMillimeters)
            NumericFieldRow(title: "Rear depth", unit: "mm", value: $draft.rearDepthMillimeters)
            NumericFieldRow(title: "Front protrusion", unit: "mm", value: $draft.frontProtrusionMillimeters)
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
        VStack(alignment: .leading, spacing: 12) {
            NumericFieldRow(title: "Rated power", unit: "W", value: $draft.ratedPowerWatts)
            NumericFieldRow(title: "Recommended high-pass", unit: "Hz", value: $draft.recommendedHighPassHz)
        }
    }
}

private struct ExpandAllToggle: View {
    let sections: SectionExpansionState

    var body: some View {
        HStack {
            Spacer()
            Button {
                sections.setAll(!sections.allExpanded)
            } label: {
                Label(
                    sections.allExpanded ? "Collapse all" : "Expand all",
                    systemImage: sections.allExpanded ? "chevron.up.circle" : "chevron.down.circle"
                )
            }
        }
    }
}

private struct ApplyBar: View {
    let driverID: UUID
    let validationError: String?
    let onApply: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("View 3D Model", systemImage: "cube") {
                    openWindow(id: WorkbenchLayout.driver3DModelWindowID, value: driverID)
                }
                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Apply", action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .background(.bar)
    }
}

private extension SpecificationOrigin {
    var displayName: String {
        switch self {
        case .unknown: String(localized: "Unknown")
        case .userProvided: String(localized: "User provided")
        case .datasheet: String(localized: "Datasheet")
        }
    }
}
