import NeXTsoundWorkbench
import SwiftUI

@main
struct NeXTsoundApp: App {
    @State private var model = WorkbenchModel(storage: try? ProfileLibraryStore.standard(), boards: BoardMonitor())
    @State private var driverLibrary = DriverLibraryModel(storage: DriverLibraryStore.standard())

    var body: some Scene {
        WindowGroup {
            WorkbenchView(model: model)
                .task { await model.start() }
                .task { await driverLibrary.start() }
        }
        .defaultSize(width: WorkbenchLayout.defaultSize.width, height: WorkbenchLayout.defaultSize.height)
        .windowResizability(.contentMinSize)

        Window(WorkbenchLayout.driverLibraryWindowTitle, id: WorkbenchLayout.driverLibraryWindowID) {
            DriverLibraryView(model: driverLibrary)
        }
        .defaultSize(width: 640, height: 480)

        WindowGroup(WorkbenchLayout.driver3DModelWindowTitle, id: WorkbenchLayout.driver3DModelWindowID, for: UUID.self) { $driverID in
            if let driverID {
                Driver3DModelWindow(model: driverLibrary, driverID: driverID)
            }
        }
        .defaultSize(width: 480, height: 480)
    }
}
