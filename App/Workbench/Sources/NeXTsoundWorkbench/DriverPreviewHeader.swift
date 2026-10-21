import AppKit
import NeXTsoundCore
import SceneKit
import SceneKit.ModelIO
import SwiftUI

/// Shows the driver's 3D model when one is bundled, falling back to a static image, and to a
/// neutral placeholder when neither is available. Always shown above the collapsible sections,
/// never itself collapsible. Uses SceneKit rather than RealityKit's `Model3D`, which is
/// unavailable on macOS.
struct DriverPreviewHeader: View {
    static let minimumHeight: CGFloat = 120
    static let maximumHeight: CGFloat = 600

    let driver: DriverRecord
    @AppStorage("driverForm.previewHeight") private var height = 200.0
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let model3DAssetName = driver.model3DAssetName, let scene = Self.loadScene(named: model3DAssetName) {
                    SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
                } else {
                    imageOrPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            ResizeHandle(height: $height, dragStartHeight: $dragStartHeight)
        }
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ResizeHandle: View {
    @Binding var height: Double
    @Binding var dragStartHeight: CGFloat?

    var body: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 5)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartHeight == nil {
                            dragStartHeight = height
                        }
                        let proposed = (dragStartHeight ?? height) + value.translation.height
                        height = min(max(proposed, DriverPreviewHeader.minimumHeight), DriverPreviewHeader.maximumHeight)
                    }
                    .onEnded { _ in
                        dragStartHeight = nil
                    }
            )
            .help("Drag to resize the preview")
    }
}

private extension DriverPreviewHeader {
    /// Loaded through Model I/O rather than `SCNScene(url:)` directly, since SceneKit's own
    /// loader does not import STL; `MDLAsset` does (`kUTTypeStereolithography`).
    static func loadScene(named name: String) -> SCNScene? {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: nil),
            MDLAsset.canImportFileExtension(url.pathExtension)
        else {
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

private extension DriverPreviewHeader {
    @ViewBuilder var imageOrPlaceholder: some View {
        if let imageAssetName = driver.imageAssetName {
            Image(imageAssetName, bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(16)
        } else {
            ContentUnavailableView(
                "No model available",
                systemImage: "cube.transparent",
                description: Text("Add a USDZ model or an image to show it here.")
            )
        }
    }
}
