import SwiftUI

/// The front panel's motion, all in one ease: 180 ms for a change of state, 80 ms with reduced motion, and
/// 400 ms for the display's status column to slide in or out.
enum FrontPanelMotion {
    static func state(reduceMotion: Bool) -> Animation {
        ease(duration: reduceMotion ? 0.08 : 0.18)
    }

    /// The status column's slide, or none with reduced motion, so the column appears and disappears at once.
    static func slide(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : ease(duration: 0.4)
    }
}

private extension FrontPanelMotion {
    /// The ease every motion on the front panel shares.
    static func ease(duration: Double) -> Animation {
        .timingCurve(0.3, 0.7, 0.4, 1, duration: duration)
    }
}
