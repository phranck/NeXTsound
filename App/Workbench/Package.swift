// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NeXTsoundWorkbench",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "NeXTsoundWorkbench", targets: ["NeXTsoundWorkbench"]),
        .executable(name: "NeXTsoundWorkbenchRender", targets: ["NeXTsoundWorkbenchRender"]),
        .executable(name: "NeXTsoundDiagnostics", targets: ["NeXTsoundDiagnostics"]),
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
            resources: [
                .process("Resources/Localizable.xcstrings"),
                .copy("Resources/Fonts"),
                // Built by Scripts/bootstrap-picotool-usb.sh and Scripts/firmware.sh; neither is
                // committed, see .gitignore.
                .copy("Resources/picotool"),
                .copy("Resources/nxs_firmware.uf2"),
            ]
        ),
        .executableTarget(
            name: "NeXTsoundWorkbenchRender",
            dependencies: ["NeXTsoundWorkbench", .product(name: "NeXTsoundCore", package: "Shared")],
            path: "Tools/NeXTsoundWorkbenchRender"
        ),
        .executableTarget(
            name: "NeXTsoundDiagnostics",
            dependencies: ["NeXTsoundWorkbench", .product(name: "NeXTsoundCore", package: "Shared")],
            path: "Tools/NeXTsoundDiagnostics"
        ),
        .testTarget(
            name: "NeXTsoundWorkbenchTests",
            dependencies: ["NeXTsoundWorkbench", .product(name: "NeXTsoundCore", package: "Shared")]
        ),
    ]
)
