// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeXTsoundShared",
    platforms: [.macOS(.v15)],
    products: [.library(name: "NeXTsoundCore", targets: ["NeXTsoundCore"])],
    targets: [
        .target(name: "NeXTsoundProtocol", publicHeadersPath: "include"),
        .target(name: "NeXTsoundCore", dependencies: ["NeXTsoundProtocol"]),
        .testTarget(name: "NeXTsoundCoreTests", dependencies: ["NeXTsoundCore", "NeXTsoundProtocol"], resources: [.copy("Fixtures")]),
    ],
    cLanguageStandard: .c11
)
