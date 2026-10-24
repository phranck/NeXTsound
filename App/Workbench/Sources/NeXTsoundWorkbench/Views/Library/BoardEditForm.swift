import NeXTsoundCore
import SwiftUI

/// The form that edits the connected SoundBox's name and owner metadata, which the Library panel opens for a verified
/// board with the metadata feature.
///
/// The number field starts with the register's proposal for a board that carries none. Apply stays off while a
/// problem blocks writing, and every problem stands below the fields in the normal text size, dimmed.
struct BoardEditForm: View {
    let register: SerialNumberRegister?
    let chip: String
    let onSubmit: (String, OwnerMetadata) -> Void
    @State private var draft: BoardEditDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SoundBox")
                .font(.headline)
            Form {
                TextField("Name", text: $draft.name)
                TextField("Owner", text: $draft.owner)
                LabeledContent("Unit") {
                    HStack(spacing: 4) {
                        Text(verbatim: SerialNumberFormat.prefix)
                        TextField("Unit", text: $draft.unitDigits, prompt: Text(verbatim: "0001"))
                            .labelsHidden()
                            .frame(width: 96)
                    }
                }
                LabeledContent("Date") {
                    HStack {
                        Toggle("Date", isOn: $draft.hasDate)
                            .labelsHidden()
                        DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                            .labelsHidden()
                            .disabled(!draft.hasDate)
                    }
                }
                TextField("Note", text: $draft.note, axis: .vertical)
                    .lineLimit(3 ... 6)
            }
            .frame(width: 340)
            ProblemList(problems: problems)
            Text("The new name appears in macOS only after the board resets or is replugged.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Apply") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problems.contains(where: \.blocksWriting))
            }
        }
        .padding(16)
        .frame(width: 372)
    }

    /// - Parameters:
    ///   - capabilities: The board's capabilities, whose name the form starts with.
    ///   - metadata: The metadata the board carries.
    ///   - register: The serial-number register, or nil while it cannot be read.
    ///   - onSubmit: Receives the name and the metadata to write.
    init(
        capabilities: DeviceCapabilities,
        metadata: OwnerMetadata,
        register: SerialNumberRegister?,
        onSubmit: @escaping (String, OwnerMetadata) -> Void
    ) {
        self.register = register
        chip = capabilities.serial
        self.onSubmit = onSubmit
        let proposal = register?.proposal(for: capabilities.serial) ?? 1
        _draft = State(initialValue: BoardEditDraft(capabilities: capabilities, metadata: metadata, proposedNumber: proposal))
    }
}

private extension BoardEditForm {
    var problems: [BoardEditProblem] {
        draft.problems(register: register, chip: chip)
    }

    func submit() {
        guard
            !problems.contains(where: \.blocksWriting),
            let metadata = draft.metadata()
        else {
            return
        }
        onSubmit(draft.name, metadata)
    }
}

/// The form's problems, a blocking one with a circled mark and a warning with a triangle.
private struct ProblemList: View {
    let problems: [BoardEditProblem]

    var body: some View {
        if !problems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(problems.indices, id: \.self) { index in
                    let problem = problems[index]
                    Label(problem.message, systemImage: problem.blocksWriting ? "exclamationmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
