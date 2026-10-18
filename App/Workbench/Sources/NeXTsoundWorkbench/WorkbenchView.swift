import AppKit
import NeXTsoundCore
import SwiftUI

public struct WorkbenchView: View {
    @Binding private var document: ProfileDocument
    private let fileURL: URL?
    @State private var errorMessage: String?

    public var body: some View {
        NavigationSplitView {
            ProfileSidebar(profile: document.profile, fileURL: fileURL, applyPreset: applyPreset)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            WorkbenchEditor(profile: profileBinding)
        }
        .font(.body)
        .tint(WorkbenchTheme.amber)
        .frame(minWidth: WorkbenchLayout.minimumSize.width, minHeight: WorkbenchLayout.minimumSize.height)
        .toolbar {
            ToolbarItemGroup {
                DocumentActions()
            }
        }
        .alert("The profile could not be changed", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Check the profile values.")
        }
    }

    public init(document: Binding<ProfileDocument>, fileURL: URL? = nil) {
        _document = document
        self.fileURL = fileURL
    }
}

private extension WorkbenchView {
    var profileBinding: Binding<SoundProfile> {
        Binding(get: { document.profile }, set: { proposed in
            do {
                try document.edit { $0 = proposed }
            } catch {
                errorMessage = error.localizedDescription
            }
        })
    }

    var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })
    }

    func applyPreset(_ preset: FactoryPreset) {
        do {
            try document.apply(preset)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DocumentActions: View {
    var body: some View {
        ControlGroup {
            Button("Open profile", systemImage: "folder") {
                NSDocumentController.shared.openDocument(nil)
            }
            Button("Save profile", systemImage: "square.and.arrow.down") {
                NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
            }
        }
        .controlSize(.regular)
    }
}
