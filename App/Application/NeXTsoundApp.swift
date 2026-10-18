import NeXTsoundWorkbench
import SwiftUI

@main
struct NeXTsoundApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: ProfileDocument()) { configuration in
            WorkbenchView(document: configuration.$document, fileURL: configuration.fileURL)
        }
        .defaultSize(width: WorkbenchLayout.defaultSize.width, height: WorkbenchLayout.defaultSize.height)
    }
}
