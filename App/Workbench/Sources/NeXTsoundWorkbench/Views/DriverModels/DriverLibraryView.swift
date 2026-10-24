import NeXTsoundCore
import SwiftUI

/// The Driver Models window: the list of driver models beside the form that edits the selected one.
///
/// Delete asks before it removes a driver model, and the form's Apply saves the edit once it validates.
public struct DriverLibraryView: View {
    @Bindable var model: DriverLibraryModel
    @State private var selection = DriverModelSelection()
    @State private var isConfirmingDelete = false

    public init(model: DriverLibraryModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            DriverListColumn(
                drivers: model.drivers,
                selection: selectedID,
                canDelete: selection.canDelete,
                onAdd: model.addDriver,
                onDelete: { isConfirmingDelete = true }
            )
        } detail: {
            if let draft = selection.draft {
                DriverForm(draft: draftBinding(for: draft), validationError: selection.validationError) {
                    selection.apply(to: model)
                }
                .id(draft.id)
            } else {
                ContentUnavailableView("No driver model selected", systemImage: "waveform.circle")
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .confirmationDialog("Delete this driver model?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                selection.deleteSelected(from: model)
            }
        } message: {
            Text("This can't be undone.")
        }
        .alert("The driver model could not be changed", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Check the driver model values.")
        }
        .onChange(of: model.drivers) { _, drivers in
            selection.refresh(from: drivers)
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

    var selectedID: Binding<UUID?> {
        Binding {
            selection.selectedID
        } set: { identifier in
            selection.select(identifier, in: model.drivers)
        }
    }

    func draftBinding(for driver: DriverRecord) -> Binding<DriverRecord> {
        Binding(get: { selection.draft ?? driver }, set: { selection.draft = $0 })
    }
}

private struct DriverListColumn: View {
    let drivers: [DriverRecord]
    @Binding var selection: UUID?
    let canDelete: Bool
    let onAdd: () -> Void
    let onDelete: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(drivers) { driver in
                Text(driver.displayName)
                    .tag(driver.id)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                ControlGroup {
                    Button("New driver model", systemImage: "plus", action: onAdd)
                        .help("Add a new driver model")
                    Button("Delete driver model", systemImage: "minus", action: onDelete)
                        .disabled(!canDelete)
                        .help("Delete the selected driver model")
                }
                .controlSize(.regular)
            }
        }
    }
}
