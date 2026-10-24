import Foundation

/// Which message the display's overlay shows, as the model's messages come and go.
///
/// An error shows at once and stays while it is current. Any other message shows once it has stayed current for
/// `settleDelay`, so a state that passes in a moment, such as a profile save after every edit, never flashes up. It
/// leaves after `showDuration`, unless it lasts while current, as a save to the SoundBox does. A message that was the
/// last one shown does not show again until another one has, so the hint that edits play live appears once rather
/// than after every save.
struct FrontPanelMessageOverlay: Equatable {
    /// How long a message that is not an error has to stay current before it shows.
    static let settleDelay = Duration.milliseconds(500)
    /// How long a message that is not an error stays shown.
    static let showDuration = Duration.seconds(4)

    /// The message the overlay shows, or nil while it shows none.
    private(set) var shown: FrontPanelMessage?
    private var lastShownText: String?
}

extension FrontPanelMessageOverlay {
    /// Takes the model's current message. Returns how long to wait before calling `settle(_:)` with it, or nil when
    /// nothing has to wait: an error shows at once, and no message or the last one shown needs nothing.
    mutating func receive(_ message: FrontPanelMessage?) -> Duration? {
        guard let message else {
            shown = nil
            lastShownText = nil
            return nil
        }
        if message.isError {
            show(message)
            return nil
        }
        if shown != message {
            shown = nil
        }
        return message.text == lastShownText ? nil : Self.settleDelay
    }

    /// Shows a message that stayed current. Returns how long it stays before calling `expire(_:)`, or nil when it
    /// stays while current.
    mutating func settle(_ message: FrontPanelMessage) -> Duration? {
        show(message)
        return message.isLasting ? nil : Self.showDuration
    }

    /// Hides the message once its time is up, unless another one took its place.
    mutating func expire(_ message: FrontPanelMessage) {
        if shown == message {
            shown = nil
        }
    }
}

private extension FrontPanelMessageOverlay {
    mutating func show(_ message: FrontPanelMessage) {
        shown = message
        lastShownText = message.text
    }
}
