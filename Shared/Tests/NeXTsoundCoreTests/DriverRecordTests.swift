import Foundation
import Testing
@testable import NeXTsoundCore

struct DriverRecordTests {
    @Test func theSeedDriverValidates() throws {
        try DriverRecord.tectonicTEBM28C10_4().validate()
    }

    @Test func theSeedDriverUsesTheFullDatasheetParameterSet() {
        let driver = DriverRecord.tectonicTEBM28C10_4()
        #expect(driver.nominalImpedanceOhms == 4)
        #expect(driver.reOhms == 4.40)
        #expect(driver.leMillihenries == 0.09)
        #expect(driver.blTeslaMeters == 2.87)
        #expect(driver.fsHz == 130)
        #expect(driver.qts == 0.39)
        #expect(driver.qes == 0.45)
        #expect(driver.qms == 2.74)
        #expect(driver.vasLiters == 0.15)
        #expect(driver.sdSquareCentimeters == 8.55)
        #expect(driver.mmsGrams == 1.0)
        #expect(driver.xmaxMillimeters == 4.0)
        #expect(driver.frameDiameterMillimeters == 46)
        #expect(driver.mountingPitchCircleDiameterMillimeters == 48.0)
        #expect(driver.mountingHoleCount == 4)
        #expect(driver.ratedPowerWatts == 10)
        #expect(driver.mountingHoleDiameterMillimeters == nil)
        #expect(driver.rearDepthMillimeters == nil)
        #expect(driver.frontProtrusionMillimeters == nil)
    }

    @Test func anEmptyNameIsRejected() {
        let driver = DriverRecord(name: "   ")
        #expect(throws: DriverValidationError.missingName) { try driver.validate() }
    }

    @Test(arguments: [0.0, -1.0, Double.infinity, -Double.infinity, Double.nan])
    func invalidNumericValuesAreRejected(_ value: Double) {
        var driver = DriverRecord()
        driver.fsHz = value
        #expect(throws: DriverValidationError.invalidValue(.resonantFrequency)) { try driver.validate() }
    }

    @Test func aNonPositiveMountingHoleCountIsRejected() {
        var driver = DriverRecord()
        driver.mountingHoleCount = 0
        #expect(throws: DriverValidationError.invalidValue(.mountingHoleCount)) { try driver.validate() }
    }

    @Test func nonHTTPSourceURLsAreRejected() {
        var driver = DriverRecord()
        driver.sourceURLs = [URL(fileURLWithPath: "/tmp/untrusted")]
        #expect(throws: DriverValidationError.invalidSourceURL) { try driver.validate() }
    }

    @Test func aDatasheetOriginRequiresASource() throws {
        var driver = DriverRecord()
        driver.origin = .datasheet
        #expect(throws: DriverValidationError.missingDatasheetSource) { try driver.validate() }
        driver.sourceURLs = try [#require(URL(string: "https://example.com/datasheet.pdf"))]
        try driver.validate()
    }

    @Test func missingValuesStayAbsent() {
        let driver = DriverRecord(name: "Unspecified")
        #expect(driver.fsHz == nil)
        #expect(driver.qts == nil)
        #expect(driver.sourceURLs.isEmpty)
        #expect(driver.origin == .unknown)
    }

    @Test func aDriverRoundTripsThroughJSON() throws {
        let driver = DriverRecord.tectonicTEBM28C10_4()
        let data = try JSONEncoder().encode(driver)
        let decoded = try JSONDecoder().decode(DriverRecord.self, from: data)
        #expect(decoded == driver)
    }
}
