import NeXTsoundWorkbench
import SwiftUI

@main
struct NeXTsoundApp: App {
    @State private var model = WorkbenchModel(storage: try? ProfileLibraryStore.standard(), boards: BoardMonitor())
    @State private var driverLibrary = DriverLibraryModel(storage: try? DriverLibraryStore.standard())
    @State private var libraryWindow = LibraryWindowAttachment()

    var body: some Scene {
        // The front panel is the app's one main window, so the app quits when it closes, and the window needs no item
        // in the Window menu. Removing the scene's commands takes that item away, so the app's own commands are added
        // after the removal.
        Window(WorkbenchLayout.frontPanelWindowTitle, id: WorkbenchLayout.frontPanelWindowID) {
            FrontPanelView(model: model, libraryWindow: libraryWindow)
                .task { await model.start() }
                .task { await driverLibrary.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()
        .commands {
            FrontPanelCommands()
            LibraryCommands()
            CommandGroup(before: .sidebar) {
                WindowVisibilityToggle(windowID: WorkbenchLayout.libraryWindowID)
            }
        }

        // The Library window is an ordinary window rather than a utility window, because a utility window hides while
        // the app is inactive, and hiding a child window detaches it from the front panel window it is glued to. The
        // front panel's key and the View menu's toggle show and hide it, so it needs no item in the Window menu.
        Window(WorkbenchLayout.libraryWindowTitle, id: WorkbenchLayout.libraryWindowID) {
            LibraryPanel(model: model, driverLibrary: driverLibrary, libraryWindow: libraryWindow)
                .windowMinimizeBehavior(.disabled)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()

        Window(WorkbenchLayout.driverLibraryWindowTitle, id: WorkbenchLayout.driverLibraryWindowID) {
            DriverLibraryView(model: driverLibrary)
        }
        .defaultSize(width: 640, height: 480)
    }
}
