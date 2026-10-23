import SwiftUI

/// The app menu's About item, which opens the app's own About window in place of the standard panel.
public struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(WorkbenchWindows.aboutWindowTitle) {
                openWindow(id: WorkbenchWindows.aboutWindowID)
            }
        }
    }

    public init() {}
}
