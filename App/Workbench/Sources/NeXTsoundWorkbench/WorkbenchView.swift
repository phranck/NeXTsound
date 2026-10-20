import AppKit
import NeXTsoundCore
import SwiftUI
import UniformTypeIdentifiers

public struct WorkbenchView: View {
    @Bindable private var model: WorkbenchModel
    @Bindable private var driverLibrary: DriverLibraryModel
    @Environment(\.undoManager) private var undoManager
    @State private var isShowingDriverLibrary = false

    public var body: some View {
        NavigationSplitView {
            ProfileSidebar(model: model, undoManager: undoManager)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            WorkbenchEditor(
                profile: profileBinding,
                connectionState: model.boards.state,
                slotA: model.slotA,
                slotB: model.slotB,
                onRenameBoard: { await model.renameBoard($0) },
                onCaptureA: { model.captureSlotA() },
                onRecallA: { model.recallSlotA(undoManager: undoManager) },
                onCaptureB: { model.captureSlotB() },
                onRecallB: { model.recallSlotB(undoManager: undoManager) }
            )
        }
        .font(.body)
        .tint(WorkbenchTheme.amber)
        .frame(minWidth: WorkbenchLayout.minimumSize.width, minHeight: WorkbenchLayout.minimumSize.height)
        .toolbar {
            ToolbarItemGroup {
                ProfileActions(model: model, undoManager: undoManager)
            }
            ToolbarItemGroup {
                Button("Driver models", systemImage: "waveform.circle") { isShowingDriverLibrary = true }
                    .help("Manage the driver models used to calculate a sound profile")
            }
            ToolbarItemGroup {
                Button("Send to SoundBox", systemImage: "hifispeaker.fill") { Task { await model.applyToBoard() } }
                    .disabled(!isBoardVerified)
                    .help("Apply the current profile to the connected SoundBox for live listening, without persisting it")
            }
        }
        .sheet(isPresented: $isShowingDriverLibrary) {
            DriverLibraryView(model: driverLibrary)
        }
        .task { await driverLibrary.start() }
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.neXTsoundProfile, .json]) { result in
            guard case let .success(url) = result else {
                return
            }
            Task { await model.importProfile(at: url, undoManager: undoManager) }
        }
        .fileExporter(
            isPresented: $model.isExporting,
            document: ProfileFile(profile: model.profile),
            contentType: .neXTsoundProfile,
            defaultFilename: model.profile.name.isEmpty ? "Untitled" : model.profile.name
        ) { _ in }
        .alert("The profile could not be changed", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Check the profile values.")
        }
    }

    public init(model: WorkbenchModel, driverLibrary: DriverLibraryModel) {
        self.model = model
        self.driverLibrary = driverLibrary
    }
}

private extension WorkbenchView {
    var profileBinding: Binding<SoundProfile> {
        Binding(get: { model.profile }, set: { model.updateProfile($0, undoManager: undoManager) })
    }

    var errorIsPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: {
            if !$0 {
                model.errorMessage = nil
            }
        })
    }

    var isBoardVerified: Bool {
        if case .verified = model.boards.state {
            return true
        }
        return false
    }
}

private struct ProfileActions: View {
    let model: WorkbenchModel
    let undoManager: UndoManager?

    var body: some View {
        ControlGroup {
            Button("New profile", systemImage: "plus") { model.addProfile(undoManager: undoManager) }
                .help("Add a new sound profile")
            Button("Delete profile", systemImage: "minus") { model.removeProfile(undoManager: undoManager) }
                .help("Delete the selected sound profile")
        }
        .controlSize(.regular)
        ControlGroup {
            Button("Import profile", systemImage: "square.and.arrow.down") { model.isImporting = true }
                .help("Import a sound profile from a file")
            Button("Export profile", systemImage: "square.and.arrow.up") { model.isExporting = true }
                .help("Export the selected sound profile to a file")
        }
        .controlSize(.regular)
    }
}
