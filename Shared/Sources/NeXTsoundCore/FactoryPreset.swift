import Foundation

public enum FactoryPreset: String, CaseIterable, Identifiable, Sendable {
    case flat
    case warm
    case speech

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .flat: String(localized: "Flat")
        case .warm: String(localized: "Warm")
        case .speech: String(localized: "Speech")
        }
    }
}

public extension FactoryPreset {
    func makeProfile() -> SoundProfile {
        var settings = DSPSettings()
        switch self {
        case .flat:
            break
        case .warm:
            settings.bands[0].gainDb = 2
            settings.bands[3].gainDb = -1.5
        case .speech:
            settings.highPassEnabled = true
            settings.highPassHz = 150
            settings.bands[3].gainDb = 2
        }
        var profile = SoundProfile(name: name, settings: settings)
        profile.presetOrigin = rawValue
        return profile
    }
}
