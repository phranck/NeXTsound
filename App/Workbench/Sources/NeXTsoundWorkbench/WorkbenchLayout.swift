import CoreGraphics
import Foundation

public enum WorkbenchLayout {
    public static let minimumSize = CGSize(width: 1080, height: 680)
    public static let defaultSize = CGSize(width: 1280, height: 860)
    public static let driverLibraryWindowID = "driver-library"
    public static let driver3DModelWindowID = "driver-3d-model"
    /// A plain, already-localized `String` rather than a `LocalizedStringKey`: the App target has
    /// no String Catalog of its own, so a literal passed directly to `Window(_:id:)` there would
    /// never extract. This resolves through the Workbench package's own catalog instead.
    public static let driverLibraryWindowTitle = String(localized: "Driver Models")
    public static let driver3DModelWindowTitle = String(localized: "3D Model")
}
