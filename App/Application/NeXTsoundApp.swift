import AppKit
import NeXTsoundWorkbench
import SwiftUI

@main
struct NeXTsoundApp: App {
    @State private var model = WorkbenchModel(
        storage: try? ProfileLibraryStore.standard(),
        boards: BoardMonitor(),
        serialNumberStorage: try? SerialNumberRegisterStore.standard()
    )
    @State private var driverLibrary = DriverLibraryModel(storage: try? DriverLibraryStore.standard())

    var body: some Scene {
        // The front panel is the app's one main window, so closing it quits the app, and the window needs no item in
        // the Window menu. With the Driver Models and About windows declared beside it, SwiftUI no longer quits by
        // itself, so the panel quits the app when its window closes. Removing the scene's commands takes the menu item
        // away, so the app's own commands are added after the removal. The Library is a sheet on this window.
        Window(WorkbenchWindows.frontPanelWindowTitle, id: WorkbenchWindows.frontPanelWindowID) {
            FrontPanelView(model: model, driverLibrary: driverLibrary)
                .task { await model.start() }
                .task { await driverLibrary.start() }
                .onWindowClose { NSApplication.shared.terminate(nil) }
                .opensInTitledWindow()
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
                .opensInTitledWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
        .commandsRemoved()
    }
}
