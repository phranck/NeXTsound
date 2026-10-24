import Testing
@testable import NeXTsoundWorkbench

struct AboutInfoTests {
    @Test func theVersionBuildAndCopyrightComeFromTheInfoPlist() {
        let plist = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1", "NSHumanReadableCopyright": "© 2026 LAYERED.work"]
        let info = AboutInfo { key in plist[key] }
        #expect(info == AboutInfo(version: "0.1.0", build: "1", copyright: "© 2026 LAYERED.work"))
        #expect(info.versionLine == "Version 0.1.0 (1)")
    }

    @Test func aBundleWithoutACopyrightShowsNone() {
        let plist = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"]
        #expect(AboutInfo { key in plist[key] }.copyright == nil)
    }
}
