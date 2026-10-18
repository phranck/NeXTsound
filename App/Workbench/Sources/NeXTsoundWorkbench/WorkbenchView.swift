import AppKit
import NeXTsoundCore
import SwiftUI
import UniformTypeIdentifiers

public struct WorkbenchView: View {
    @Bindable private var model: WorkbenchModel
    @Environment(\.undoManager) private var undoManager

    public var body: some View {
        NavigationSplitView {
            ProfileSidebar(model: model, undoManager: undoManager)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            WorkbenchEditor(profile: profileBinding, connectionState: model.boards.state)
        }
        .font(.body)
        .tint(WorkbenchTheme.amber)
        .frame(minWidth: WorkbenchLayout.minimumSize.width, minHeight: WorkbenchLayout.minimumSize.height)
        .toolbar {
            ToolbarItemGroup {
                ProfileActions(model: model, undoManager: undoManager)
            }
        }
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

    public init(model: WorkbenchModel) {
        self.model = model
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
}

private struct ProfileActions: View {
    let model: WorkbenchModel
    let undoManager: UndoManager?

    var body: some View {
        ControlGroup {
            Button("New profile", systemImage: "plus") { model.addProfile(undoManager: undoManager) }
            Button("Delete profile", systemImage: "minus") { model.removeProfile(undoManager: undoManager) }
        }
        .controlSize(.regular)
        ControlGroup {
            Button("Import profile", systemImage: "square.and.arrow.down") { model.isImporting = true }
            Button("Export profile", systemImage: "square.and.arrow.up") { model.isExporting = true }
        }
        .controlSize(.regular)
    }
}
