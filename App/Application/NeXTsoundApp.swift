import NeXTsoundWorkbench
import SwiftUI

@main
struct NeXTsoundApp: App {
    @State private var model = WorkbenchModel(storage: try? ProfileLibraryStore.standard())

    var body: some Scene {
        WindowGroup {
            WorkbenchView(model: model)
                .task { await model.start() }
        }
        .defaultSize(width: WorkbenchLayout.defaultSize.width, height: WorkbenchLayout.defaultSize.height)
        .windowResizability(.contentMinSize)
    }
}
