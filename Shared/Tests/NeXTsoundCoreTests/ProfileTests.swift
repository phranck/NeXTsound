import Foundation
import Testing
@testable import NeXTsoundCore

struct ProfileTests {
    @Test func namedProfileRoundTripPreservesSpeakerAndEnclosure() throws {
        var profile = FactoryPreset.warm.makeProfile()
        profile.name = "Desk speaker"
        var speaker = SpeakerRecord(name: "My driver")
        speaker.nominalImpedanceOhms = 8
        speaker.origin = .userProvided
        profile.speaker = speaker
        var enclosure = EnclosureRecord(name: "Printed shell")
        enclosure.volume = EnclosureVolume(internalLiters: 0.7, displacementLiters: 0.1, origin: .model)
        enclosure.modelReference = ModelReference(fileName: "shell.step", revision: "1", sha256: String(repeating: "a", count: 64))
        profile.enclosure = enclosure
        #expect(try SoundProfile.decode(profile.encoded()) == profile)
        #expect(try abs(#require(profile.enclosure?.volume?.netLiters) - 0.6) < 0.000_001)
    }

    @Test func unknownSpeakerAndVolumeDataRemainAbsent() throws {
        var profile = SoundProfile(name: "Unspecified")
        profile.speaker = SpeakerRecord()
        profile.enclosure = EnclosureRecord()
        let restored = try SoundProfile.decode(profile.encoded())
        #expect(restored.speaker?.nominalImpedanceOhms == nil)
        #expect(restored.speaker?.ratedPowerWatts == nil)
        #expect(restored.enclosure?.volume == nil)
    }

    @Test func catalogChangesDoNotAlterProfileSnapshots() {
        var catalogEntry = SpeakerRecord(name: "Original driver")
        var profile = SoundProfile(name: "Desk")
        profile.speaker = catalogEntry
        catalogEntry.name = "Renamed driver"
        catalogEntry.ratedPowerWatts = 5
        #expect(profile.speaker?.name == "Original driver")
        #expect(profile.speaker?.ratedPowerWatts == nil)
    }

    @Test func rejectsUnknownProfileVersionsBeforeDecodingTheirContents() throws {
        let data = Data("{\"formatVersion\":999}".utf8)
        #expect(throws: ProfileValidationError.unsupportedFormat(999)) { try SoundProfile.decode(data) }
    }

    @Test func jsonDecoderAlsoRejectsInvalidProfileContents() throws {
        let validData = try SoundProfile(name: "Valid").encoded()
        var document = try #require(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        var settings = try #require(document["settings"] as? [String: Any])
        var bands = try #require(settings["bands"] as? [[String: Any]])
        bands[0]["frequencyHz"] = 99999
        settings["bands"] = bands
        document["settings"] = settings
        let data = try JSONSerialization.data(withJSONObject: document)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SoundProfile.self, from: data) }
    }

    @Test func directEncodersRejectInvalidProfiles() {
        var profile = SoundProfile(name: "Invalid")
        profile.settings.bands[0].frequencyHz = 99999
        #expect(throws: (any Error).self) { try JSONEncoder().encode(profile) }
    }

    @Test func invalidRevisionsCannotWrapOrBeSaved() {
        var profile = SoundProfile(name: "Revision")
        profile.revision = 0
        #expect(throws: ProfileValidationError.invalidRevision) { try profile.encoded() }
        profile.revision = .max
        #expect(throws: ProfileValidationError.invalidRevision) { try profile.advanceRevision() }
        #expect(profile.revision == .max)
    }

    @Test(arguments: [0.0, -1.0, Double.infinity, -Double.infinity, Double.nan])
    func invalidSpeakerValuesAreRejected(_ impedance: Double) {
        var speaker = SpeakerRecord()
        speaker.nominalImpedanceOhms = impedance
        #expect(throws: ProfileValidationError.invalidSpeaker) { try speaker.validate() }
    }

    @Test func datasheetSpecificationsRequireASource() {
        var speaker = SpeakerRecord()
        speaker.origin = .datasheet
        #expect(throws: ProfileValidationError.invalidSpeaker) { try speaker.validate() }
        speaker.sourceURLs = [URL(fileURLWithPath: "/tmp/untrusted")]
        #expect(throws: ProfileValidationError.invalidSpeaker) { try speaker.validate() }
    }

    @Test func invalidEnclosuresCannotBeSaved() {
        var enclosure = EnclosureRecord()
        enclosure.volume = EnclosureVolume(internalLiters: 0.5, displacementLiters: 0.6)
        #expect(throws: ProfileValidationError.invalidEnclosure) { try enclosure.validate() }
        enclosure.volume = EnclosureVolume(internalLiters: 0.5, origin: .model)
        #expect(throws: ProfileValidationError.invalidEnclosure) { try enclosure.validate() }
        enclosure.modelReference = ModelReference(fileName: "shell.stl", sha256: "not-a-digest")
        #expect(throws: ProfileValidationError.invalidModelReference) { try enclosure.validate() }
    }

    @Test func factoryPresetsAreMutedListeningStartingPoints() throws {
        for preset in FactoryPreset.allCases {
            let profile = preset.makeProfile()
            try profile.validate()
            #expect(profile.settings.isMuted)
            #expect(profile.speaker == nil)
            #expect(profile.enclosure == nil)
            #expect(profile.presetOrigin == preset.rawValue)
        }
    }

    @Test func rejectsAnEmptyProfileName() {
        let profile = SoundProfile(name: " \n ")
        #expect(throws: ProfileValidationError.invalidName) { try profile.encoded() }
    }
}
