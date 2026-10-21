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
    dependencies: [
        .package(path: "../../Shared"),
        .package(url: "https://github.com/SecondMouseAU/OCCTSwift.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "NXSUSBHostShim",
            cSettings: [.unsafeFlags(["-I/opt/homebrew/include"])],
            linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib", "-lusb-1.0"])]
        ),
        .target(
            name: "NeXTsoundWorkbench",
            dependencies: [
                "NXSUSBHostShim",
                .product(name: "NeXTsoundCore", package: "Shared"),
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ],
            resources: [
                .process("Resources/Localizable.xcstrings"),
                // Built by Scripts/bootstrap-picotool-usb.sh and Scripts/firmware.sh; neither is
                // committed, see .gitignore.
                .copy("Resources/picotool"),
                .copy("Resources/nxs_firmware.uf2"),
                // The reference driver's chassis, decimated to a 0.5 mm vertex grid from the
                // owner's STL export; shown in the driver library's 3D preview.
                .copy("Resources/TEBM28C10-4-Driver.stl"),
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
            dependencies: [
                "NeXTsoundWorkbench",
                .product(name: "NeXTsoundCore", package: "Shared"),
                .product(name: "OCCTSwift", package: "OCCTSwift"),
            ]
        ),
    ]
)
