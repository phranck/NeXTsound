import Foundation

/// Why the live spectrum cannot show the SoundBox's audio. The display's message card shows the reason.
enum SpectrumError: Error, Equatable, Sendable {
    /// The audio to analyze reports no positive, finite sample rate.
    case invalidSampleRate
    /// macOS lists no audio output device for the verified SoundBox.
    case soundBoxAudioNotFound
    /// Core Audio refused to tap the SoundBox's output, for the reason it gives.
    case captureFailed(String)
}

extension SpectrumError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidSampleRate:
            String(
                localized: "The SoundBox's audio reports no usable sample rate.",
                comment: "Message on the front panel's display when the spectrum's audio has no sample rate."
            )
        case .soundBoxAudioNotFound:
            String(
                localized: "macOS lists no audio output for this SoundBox.",
                comment: "Message on the front panel's display when the spectrum finds no audio device for the board."
            )
        case let .captureFailed(reason):
            String(
                localized: "The spectrum cannot record the SoundBox's audio: \(reason)",
                comment: "Message on the front panel's display when Core Audio refuses the spectrum's tap. The argument is its reason."
            )
        }
    }
}
