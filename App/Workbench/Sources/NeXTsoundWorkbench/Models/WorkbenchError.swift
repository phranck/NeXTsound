import Foundation

/// What a profile file's edit and the response curve refuse: an edit that replaces the profile's identity or revision,
/// and a curve with an unusable sample count or scale.
public enum WorkbenchError: Error, Equatable, Sendable {
    case documentIdentityChanged
    case invalidSampleCount
    case invalidScale
}

extension WorkbenchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .documentIdentityChanged: String(localized: "An edit cannot replace the profile identity or revision.")
        case .invalidSampleCount: String(localized: "Choose between 2 and 2048 response samples.")
        case .invalidScale: String(localized: "The logarithmic control requires finite positive bounds.")
        }
    }
}
