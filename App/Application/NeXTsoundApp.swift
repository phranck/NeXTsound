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
        .commands {
            FrontPanelCommands()
            LibraryCommands()
        }

        Window(WorkbenchLayout.driverLibraryWindowTitle, id: WorkbenchLayout.driverLibraryWindowID) {
            DriverLibraryView(model: driverLibrary)
        }
        .defaultSize(width: 640, height: 480)

        Window(WorkbenchLayout.frontPanelWindowTitle, id: WorkbenchLayout.frontPanelWindowID) {
            FrontPanelView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        UtilityWindow(WorkbenchLayout.libraryWindowTitle, id: WorkbenchLayout.libraryWindowID) {
            LibraryPanel(model: model, driverLibrary: driverLibrary)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
