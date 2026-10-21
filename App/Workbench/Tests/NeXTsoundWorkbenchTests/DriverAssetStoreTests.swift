import Foundation
import OCCTSwift
import Testing
@testable import NeXTsoundWorkbench

struct DriverAssetStoreTests {
    @Test func importingAPlainFileCopiesItUnchanged() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DriverAssetStore(directory: directory)
        let sourceData = Data("solid test\nendsolid test\n".utf8)
        let source = directory.appendingPathComponent("source.stl")
        try sourceData.write(to: source)

        let driverID = UUID()
        let filename = try store.importFile(at: source, forDriver: driverID, role: "model")

        #expect(filename == "\(driverID.uuidString)-model.stl")
        let imported = try #require(store.url(forAsset: filename))
        #expect(try Data(contentsOf: imported) == sourceData)
    }

    @Test func importingASTEPFileConvertsItToSTL() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DriverAssetStore(directory: directory)

        let stepURL = directory.appendingPathComponent("box.step")
        let box = try #require(Shape.box(width: 10, height: 10, depth: 10))
        try Exporter.writeSTEP(shape: box, to: stepURL)

        let driverID = UUID()
        let filename = try store.importFile(at: stepURL, forDriver: driverID, role: "model")

        #expect(filename == "\(driverID.uuidString)-model.stl")
        let imported = try #require(store.url(forAsset: filename))
        #expect(try Data(contentsOf: imported).count > 100)
    }

    @Test func importingAMalformedSTEPFileThrowsConversionFailed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DriverAssetStore(directory: directory)
        let stepURL = directory.appendingPathComponent("broken.step")
        try Data("not a step file".utf8).write(to: stepURL)

        #expect(throws: DriverAssetStoreError.conversionFailed) {
            _ = try store.importFile(at: stepURL, forDriver: UUID(), role: "model")
        }
    }

    @Test func importingAFileWithNoExtensionThrowsMissingFileExtension() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DriverAssetStore(directory: directory)
        let source = directory.appendingPathComponent("noext")
        try Data("x".utf8).write(to: source)

        #expect(throws: DriverAssetStoreError.missingFileExtension) {
            _ = try store.importFile(at: source, forDriver: UUID(), role: "model")
        }
    }
}

private extension DriverAssetStoreTests {
    func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
