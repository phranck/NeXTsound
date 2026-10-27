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
        // away, so the app's own commands are added after the removal. The removal also takes the Edit menu's Cut, Copy
        // and Paste, which PasteboardCommands puts back. The Library is a sheet on this window.
        Window(WorkbenchWindows.frontPanelWindowTitle, id: WorkbenchWindows.frontPanelWindowID) {
            FrontPanelView(model: model, driverLibrary: driverLibrary)
                .task { await model.start() }
                .task { await driverLibrary.start() }
                // The open front panel takes every file the app is asked to open, such as a profile double-clicked in
                // the Finder. Without it, SwiftUI opens a new instance of this scene for the file, which closes the
                // window and with it the app.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in
                    Task { await model.openProfile(at: url) }
                }
                .onWindowClose { NSApplication.shared.terminate(nil) }
                .opensInTitledWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()
        .commands {
            AboutCommands()
            PasteboardCommands()
            FrontPanelCommands()
            LibraryCommands()
            LibrarySheetCommands()
            DisplayCommands()
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
