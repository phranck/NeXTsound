import NeXTsoundWorkbench
import SwiftUI

@main
struct NeXTsoundApp: App {
    @State private var model = WorkbenchModel(storage: try? ProfileLibraryStore.standard(), boards: BoardMonitor())
    @State private var driverLibrary = DriverLibraryModel(storage: try? DriverLibraryStore.standard())

    var body: some Scene {
        // The front panel is the app's one main window, so the app quits when it closes, and the window needs no item
        // in the Window menu. Removing the scene's commands takes that item away, so the app's own commands are added
        // after the removal. The Library is a sheet on this window.
        Window(WorkbenchWindows.frontPanelWindowTitle, id: WorkbenchWindows.frontPanelWindowID) {
            FrontPanelView(model: model, driverLibrary: driverLibrary)
                .task { await model.start() }
                .task { await driverLibrary.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()
        .commands {
            AboutCommands()
            FrontPanelCommands()
            LibraryCommands()
            LibrarySheetCommands()
            StatusColumnCommands()
        }

        Window(WorkbenchWindows.driverLibraryWindowTitle, id: WorkbenchWindows.driverLibraryWindowID) {
            DriverLibraryView(model: driverLibrary)
        }
        .defaultSize(width: 640, height: 480)

        // The About window opens from the app menu alone, so it has no item in the Window menu, and it opens anew
        // rather than coming back with the app.
        Window(WorkbenchWindows.aboutWindowTitle, id: WorkbenchWindows.aboutWindowID) {
            AboutPanel()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
        .commandsRemoved()
    }
}
