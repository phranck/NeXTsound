import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Presents the panels that import and export the selected profile, which the Library's keys and the File menu ask
    /// for through the model's `isImporting` and `isExporting`, while `isActive` holds.
    ///
    /// A panel opens over the window that presents it, so the front panel hands both panels to the Library sheet while
    /// the sheet is shown, and only one view presents them at a time.
    func profileFileDialogs(model: WorkbenchModel, undoManager: UndoManager?, isActive: Bool = true) -> some View {
        modifier(ProfileFileDialogs(model: model, undoManager: undoManager, isActive: isActive))
    }
}

/// The import and export panels for the selected profile.
///
/// The body reads the model's requests itself, so a change of either updates the view.
private struct ProfileFileDialogs: ViewModifier {
    let model: WorkbenchModel
    let undoManager: UndoManager?
    let isActive: Bool

    func body(content: Content) -> some View {
        let isImporting = isActive && model.isImporting
        let isExporting = isActive && model.isExporting
        content
            .fileImporter(
                isPresented: Binding { isImporting } set: { isPresented in model.isImporting = isPresented },
                allowedContentTypes: [.neXTsoundProfile, .json]
            ) { result in
                guard case let .success(url) = result else {
                    return
                }
                Task { await model.importProfile(at: url, undoManager: undoManager) }
            }
            .fileExporter(
                isPresented: Binding { isExporting } set: { isPresented in model.isExporting = isPresented },
                document: ProfileFile(profile: model.profile),
                contentType: .neXTsoundProfile,
                defaultFilename: model.profile.displayName
            ) { _ in }
    }
}
