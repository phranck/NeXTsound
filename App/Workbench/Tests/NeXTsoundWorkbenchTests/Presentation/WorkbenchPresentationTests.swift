import Foundation
import NeXTsoundCore
import Testing
@testable import NeXTsoundWorkbench

struct DriverRecordPresentationTests {
    @Test func aDriverModelWithoutANameReadsUntitled() {
        #expect(DriverRecord(name: "").displayName == String(localized: "Untitled"))
        #expect(DriverRecord(name: "Visaton FR 58").displayName == "Visaton FR 58")
    }

    /// The form edits the sources as text with one URL per line, and the first of them is the datasheet.
    @Test func theSourcesReadAsOneURLPerLine() throws {
        let datasheet = try #require(URL(string: "https://example.com/fr58.pdf"))
        let notes = try #require(URL(string: "https://example.com/notes"))
        #expect(DriverRecord.sourceURLs(fromText: "  https://example.com/fr58.pdf \n\n https://example.com/notes\n") == [datasheet, notes])
        var driver = DriverRecord(name: "Visaton FR 58")
        #expect(driver.datasheetURL == nil)
        driver.sourceURLs = [datasheet, notes]
        #expect(driver.sourceURLText == "https://example.com/fr58.pdf\nhttps://example.com/notes")
        #expect(driver.datasheetURL == datasheet)
    }

    @Test func anEmptyManufacturerOrModelMeansNone() {
        var driver = DriverRecord(name: "Visaton FR 58")
        driver.manufacturerText = "Visaton"
        driver.modelText = "FR 58"
        #expect(driver.manufacturer == "Visaton")
        #expect(driver.model == "FR 58")
        driver.manufacturerText = ""
        driver.modelText = ""
        #expect(driver.manufacturer == nil)
        #expect(driver.model == nil)
        #expect(driver.manufacturerText.isEmpty)
    }

    @Test func theMountingHoleCountRoundsToWholeHoles() {
        var driver = DriverRecord(name: "Visaton FR 58")
        driver.mountingHoleCountValue = 3.6
        #expect(driver.mountingHoleCount == 4)
        #expect(driver.mountingHoleCountValue == 4)
        driver.mountingHoleCountValue = nil
        #expect(driver.mountingHoleCount == nil)
    }
}

struct BoardConnectionStatePresentationTests {
    @Test func onlyAVerifiedBoardHasCapabilities() {
        let capabilities = fixtureCapabilities()
        #expect(BoardConnectionState.verified(capabilities).verifiedCapabilities == capabilities)
        #expect(BoardConnectionState.disconnected.verifiedCapabilities == nil)
        #expect(BoardConnectionState.detected.verifiedCapabilities == nil)
        #expect(BoardConnectionState.mismatched("Wrong firmware").verifiedCapabilities == nil)
    }
}
