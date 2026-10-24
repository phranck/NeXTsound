import Foundation

/// The identifiers and titles of the app's windows, which the app's scenes and the views that open a window share.
public enum WorkbenchWindows {
    public static let aboutWindowID = "about"
    /// The About window's title, which the app menu's item that opens it reads as well. Localized here for the same
    /// reason as `driverLibraryWindowTitle`.
    public static let aboutWindowTitle = String(
        localized: "About NeXTsound",
        comment: "The app menu's item that opens the About window, and that window's title."
    )
    public static let driverLibraryWindowID = "driver-library"
    /// A plain, already-localized `String` rather than a `LocalizedStringKey`: the App target has
    /// no String Catalog of its own, so a literal passed directly to `Window(_:id:)` there would
    /// never extract. This resolves through the Workbench package's own catalog instead.
    public static let driverLibraryWindowTitle = String(localized: "Driver Models")
    public static let frontPanelWindowID = "front-panel"
    /// Localized here for the same reason as `driverLibraryWindowTitle`.
    public static let frontPanelWindowTitle = String(localized: "Front Panel")
}
