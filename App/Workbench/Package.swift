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
            // The static library goes into every executable that links the shim, so the app loads no libusb from outside its
            // bundle. Its own dependencies are the frameworks below, as its pkg-config Libs.private lists them.
            linkerSettings: [
                .unsafeFlags(["/opt/homebrew/opt/libusb/lib/libusb-1.0.a"]),
                .linkedLibrary("objc"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
            ]
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
            dependencies: ["NeXTsoundWorkbench", .product(name: "NeXTsoundCore", package: "Shared")],
            // An app bundle signed ad hoc once and committed, so the seal tests never start codesign themselves.
            resources: [.copy("Fixtures/SealProbe.app")]
        ),
    ]
)
