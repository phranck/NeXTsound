import Testing
@testable import NeXTsoundWorkbench

struct FirmwareVersionTests {
    @Test func readsGiteaTagsAndBoardVersions() {
        #expect(FirmwareVersion(tag: "firmware-v0.4.0") == FirmwareVersion(major: 0, minor: 4, patch: 0))
        #expect(FirmwareVersion(tag: "firmware-v12.34.56") == FirmwareVersion(major: 12, minor: 34, patch: 56))
        #expect(FirmwareVersion(boardVersion: "0.6.4") == FirmwareVersion(major: 0, minor: 6, patch: 4))
        #expect(FirmwareVersion(boardVersion: "0.6.4-dirty") == FirmwareVersion(major: 0, minor: 6, patch: 4))
    }

    @Test func rejectsMalformedVersions() {
        for version in [
            "",
            "0.4",
            "app-v0.4.0",
            "firmware-v0.4",
            "firmware-v0.4.0.0",
            "firmware-v0.4.0-dirty",
            "firmware-v01.2.3",
            "firmware-v4294967296.0.0",
        ] {
            #expect(FirmwareVersion(tag: version) == nil)
        }
        for version in ["", "0.4", "0.4.0.0", "0.04.0.0", "0.4.0-dirty-extra", "4294967296.0.0"] {
            #expect(FirmwareVersion(boardVersion: version) == nil)
        }
    }

    @Test func comparesByMajorMinorAndPatch() {
        #expect(FirmwareVersion(major: 1, minor: 0, patch: 0) > FirmwareVersion(major: 0, minor: 99, patch: 99))
        #expect(FirmwareVersion(major: 0, minor: 5, patch: 0) > FirmwareVersion(major: 0, minor: 4, patch: 99))
        #expect(FirmwareVersion(major: 0, minor: 4, patch: 1) > FirmwareVersion(major: 0, minor: 4, patch: 0))
    }
}
