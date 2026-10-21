import NeXTsoundCore
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

/// A dedicated window for a single driver's 3D model, opened from the driver form's toolbar.
/// Lets the owner add or replace the model file directly; there is no inline 3D preview in the
/// form itself.
public struct Driver3DModelWindow: View {
    @Bindable var model: DriverLibraryModel
    let driverID: UUID
    @State private var isImporting = false
    @State private var importError: String?

    public init(model: DriverLibraryModel, driverID: UUID) {
        self.model = model
        self.driverID = driverID
    }

    public var body: some View {
        Group {
            if let scene {
                SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting])
            } else {
                ContentUnavailableView(
                    "No 3D model yet",
                    systemImage: "cube.transparent",
                    description: Text("Add a USDZ, STL, or OBJ file to show it here.")
                )
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .toolbar {
            ToolbarItem {
                Button("Add 3D Model", systemImage: "square.and.arrow.down", action: { isImporting = true })
                    .help(driver?.model3DAssetName == nil ? "Add a 3D model" : "Replace the 3D model")
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.allowedContentTypes, onCompletion: handleImport)
        .alert("The 3D model could not be imported", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }
}

private extension Driver3DModelWindow {
    static let allowedContentTypes: [UTType] = [
        UTType(filenameExtension: "usdz"),
        UTType(filenameExtension: "stl"),
        UTType(filenameExtension: "obj"),
    ].compactMap(\.self)

    var driver: DriverRecord? {
        model.drivers.first(where: { $0.id == driverID })
    }

    var scene: SCNScene? {
        guard
            let driver,
            let assetName = driver.model3DAssetName,
            let url = DriverAssetStore.standard().url(forAsset: assetName)
        else {
            return nil
        }
        return DriverSceneLoader.loadScene(at: url)
    }

    var errorIsPresented: Binding<Bool> {
        Binding(get: { importError != nil }, set: {
            if !$0 {
                importError = nil
            }
        })
    }

    func handleImport(_ result: Result<URL, Error>) {
        guard var driver else {
            return
        }
        switch result {
        case let .success(url):
            do {
                let name = try DriverAssetStore.standard().importFile(at: url, forDriver: driver.id, role: "model")
                driver.model3DAssetName = name
                model.updateDriver(driver)
            } catch {
                importError = error.localizedDescription
            }
        case let .failure(error):
            importError = error.localizedDescription
        }
    }
}
