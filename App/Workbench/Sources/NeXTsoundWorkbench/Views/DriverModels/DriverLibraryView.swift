import NeXTsoundCore
import SwiftUI

public struct DriverLibraryView: View {
    @Bindable var model: DriverLibraryModel
    @State private var selectedDriverID: UUID?
    @State private var draft: DriverRecord?
    @State private var validationError: String?
    @State private var isConfirmingDelete = false

    public init(model: DriverLibraryModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            DriverListColumn(
                drivers: model.drivers,
                selection: $selectedDriverID,
                onAdd: model.addDriver,
                onDelete: { isConfirmingDelete = true }
            )
        } detail: {
            if let draft {
                DriverForm(draft: draftBinding(for: draft), validationError: validationError, onApply: applyDraft)
                    .id(draft.id)
            } else {
                ContentUnavailableView("No driver model selected", systemImage: "waveform.circle")
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .confirmationDialog("Delete this driver model?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteSelectedDriver)
        } message: {
            Text("This can't be undone.")
        }
        .alert("The driver model could not be changed", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Check the driver model values.")
        }
        .onChange(of: selectedDriverID, initial: true) { _, newValue in
            rebuildDraft(for: newValue)
        }
        .onChange(of: model.drivers) { _, _ in
            rebuildDraft(for: selectedDriverID)
        }
    }
}

private extension DriverLibraryView {
    var errorIsPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: {
            if !$0 {
                model.errorMessage = nil
            }
        })
    }

    func draftBinding(for driver: DriverRecord) -> Binding<DriverRecord> {
        Binding(get: { draft ?? driver }, set: { draft = $0 })
    }

    func rebuildDraft(for identifier: UUID?) {
        guard
            let identifier,
            let driver = model.drivers.first(where: { $0.id == identifier })
        else {
            draft = nil
            return
        }
        draft = driver
        validationError = nil
    }

    func deleteSelectedDriver() {
        guard let selectedDriverID else {
            return
        }
        let remaining = model.drivers.filter { $0.id != selectedDriverID }
        model.removeDriver(selectedDriverID)
        self.selectedDriverID = remaining.first?.id
    }

    func applyDraft() {
        guard let draft else {
            return
        }
        do {
            try draft.validate()
            model.updateDriver(draft)
            validationError = nil
        } catch {
            validationError = error.localizedDescription
        }
    }
}

private struct DriverListColumn: View {
    let drivers: [DriverRecord]
    @Binding var selection: UUID?
    let onAdd: () -> Void
    let onDelete: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(drivers) { driver in
                Text(driver.name.isEmpty ? "Untitled" : driver.name)
                    .tag(driver.id)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                ControlGroup {
                    Button("New driver model", systemImage: "plus", action: onAdd)
                        .help("Add a new driver model")
                    Button("Delete driver model", systemImage: "minus", action: onDelete)
                        .disabled(selection == nil)
                        .help("Delete the selected driver model")
                }
                .controlSize(.regular)
            }
        }
    }
}
