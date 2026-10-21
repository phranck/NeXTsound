import AppKit
import Foundation
import SceneKit
import SceneKit.ModelIO

/// Shared SceneKit loading for a driver's 3D model file, used by the 3D model window.
enum DriverSceneLoader {
    /// Loaded through Model I/O rather than `SCNScene(url:)` directly, since SceneKit's own
    /// loader does not import STL; `MDLAsset` does (`kUTTypeStereolithography`).
    static func loadScene(at url: URL) -> SCNScene? {
        guard MDLAsset.canImportFileExtension(url.pathExtension) else {
            return nil
        }
        let asset = MDLAsset(url: url)
        // MDLAsset has no `isEmpty`, only `count`.
        // swiftlint:disable:next empty_count
        guard asset.count != 0 else {
            return nil
        }
        let scene = SCNScene(mdlAsset: asset)
        scene.background.contents = NSColor(WorkbenchTheme.ink)
        return scene
    }
}
