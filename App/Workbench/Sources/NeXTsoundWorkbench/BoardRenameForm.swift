import SwiftUI

/// The form that gives the connected SoundBox a new name, which the workbench's header and the Library panel open
/// for a verified board.
struct BoardRenameForm: View {
    let currentName: String
    let onSubmit: (String) -> Void
    @State private var name: String

    init(currentName: String, onSubmit: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onSubmit = onSubmit
        _name = State(initialValue: currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SoundBox name")
                .font(.headline)
            TextField("SoundBox name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { onSubmit(name) }
            Text("The new name appears in macOS only after the board resets or is replugged.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Apply") { onSubmit(name) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}
