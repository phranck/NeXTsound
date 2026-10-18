// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeXTsoundWorkbench",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NeXTsoundWorkbench", targets: ["NeXTsoundWorkbench"]),
        .executable(name: "NeXTsoundWorkbenchRender", targets: ["NeXTsoundWorkbenchRender"]),
    ],
    dependencies: [.package(path: "../../Shared")],
    targets: [
        .target(name: "NeXTsoundWorkbench", dependencies: [.product(name: "NeXTsoundCore", package: "Shared")]),
        .executableTarget(
            name: "NeXTsoundWorkbenchRender",
            dependencies: ["NeXTsoundWorkbench", .product(name: "NeXTsoundCore", package: "Shared")],
            path: "Tools/NeXTsoundWorkbenchRender"
        ),
        .testTarget(
            name: "NeXTsoundWorkbenchTests",
            dependencies: ["NeXTsoundWorkbench", .product(name: "NeXTsoundCore", package: "Shared")]
        ),
    ]
)
