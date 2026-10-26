import Foundation
import NeXTsoundCore
import Synchronization

/// What the SoundBox does to its audio besides the audio itself: the selected profile's settings and the host's volume
/// and mute. The main actor writes them whenever they change, and the spectrum's capture reads them on its own queue
/// for every IO cycle, so an edit shows in the spectrum as it reaches the board.
final class SpectrumInputs: Sendable {
    /// One reading of the inputs.
    struct Values: Equatable, Sendable {
        var settings: DSPSettings
        /// The host's volume as the board reports it, in decibels.
        var hostVolumeDb: Float
        var hostIsMuted: Bool
    }

    private let values: Mutex<Values>

    /// Inputs that start with the board's default settings and the host at full volume.
    init() {
        values = Mutex(Values(settings: DSPSettings(), runtime: nil))
    }
}

extension SpectrumInputs {
    /// The latest values.
    var current: Values {
        get {
            values.withLock { $0 }
        }
        set {
            values.withLock { $0 = newValue }
        }
    }
}

extension SpectrumInputs.Values {
    /// The values for a profile's `settings` and the board's `runtime` status. Before the board has reported, the host
    /// counts as at full volume and not muted.
    init(settings: DSPSettings, runtime: DeviceRuntimeStatus?) {
        self.init(settings: settings, hostVolumeDb: runtime?.hostVolumeDb ?? 0, hostIsMuted: runtime?.hostIsMuted ?? false)
    }
}
