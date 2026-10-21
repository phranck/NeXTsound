import NeXTsoundWorkbench
import SwiftUI

@main
struct NeXTsoundApp: App {
    @State private var model = WorkbenchModel(storage: try? ProfileLibraryStore.standard(), boards: BoardMonitor())
    @State private var driverLibrary = DriverLibraryModel(storage: try? DriverLibraryStore.standard())

    var body: some Scene {
        WindowGroup {
            WorkbenchView(model: model, driverLibrary: driverLibrary)
                .task { await model.start() }
                .task { await driverLibrary.start() }
        }
        .defaultSize(width: WorkbenchLayout.defaultSize.width, height: WorkbenchLayout.defaultSize.height)
        .windowResizability(.contentMinSize)

        Window(WorkbenchLayout.driverLibraryWindowTitle, id: WorkbenchLayout.driverLibraryWindowID) {
            DriverLibraryView(model: driverLibrary)
        }
        .defaultSize(width: 640, height: 480)
    }
}
