import NeXTsoundCore
import SceneKit
import SwiftUI

/// Shows the driver's 3D model when one is bundled, falling back to a static image, and to a
/// neutral placeholder when neither is available. Always shown above the collapsible sections,
/// never itself collapsible. Uses SceneKit rather than RealityKit's `Model3D`, which is
/// unavailable on macOS.
struct DriverPreviewHeader: View {
    let driver: DriverRecord

    var body: some View {
        Group {
            if let model3DAssetName = driver.model3DAssetName, let scene = Self.loadScene(named: model3DAssetName) {
                SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
            } else {
                imageOrPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension DriverPreviewHeader {
    static func loadScene(named name: String) -> SCNScene? {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
            return nil
        }
        return try? SCNScene(url: url, options: nil)
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
