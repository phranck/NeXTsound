// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NeXTsoundWorkbench",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NeXTsoundWorkbench", targets: ["NeXTsoundWorkbench"]),
        .executable(name: "NeXTsoundWorkbenchRender", targets: ["NeXTsoundWorkbenchRender"]),
    ],
    dependencies: [.package(path: "../../Shared")],
    targets: [
        .target(
            name: "NXSUSBHostShim",
            cSettings: [.unsafeFlags(["-I/opt/homebrew/include"])],
            linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib", "-lusb-1.0"])]
        ),
        .target(
            name: "NeXTsoundWorkbench",
            dependencies: ["NXSUSBHostShim", .product(name: "NeXTsoundCore", package: "Shared")],
            resources: [.process("Resources")]
        ),
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
