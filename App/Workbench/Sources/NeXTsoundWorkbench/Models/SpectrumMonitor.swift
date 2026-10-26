import Foundation
import NeXTsoundCore
import Observation

/// The live spectrum of the SoundBox's audio, which the front panel's display shows while its SPECTRUM key is down.
///
/// `follow(serial:)` runs for as long as the display shows the spectrum of one verified board, and the cancellation of
/// its task stops the measurement. Each start sets the levels back to silence and clears the last problem, so a
/// released key or a board that leaves takes both with it.
@MainActor
@Observable
final class SpectrumMonitor {
    /// The defaults key of whether the display shows the spectrum, which the front panel keeps across launches.
    static let visibilityStorageKey = "frontPanelShowsSpectrum"

    /// The bands' latest levels, silent while nothing is measured.
    private(set) var levels = SpectrumLevels.silent
    /// Why the measurement could not start, which the display's message card shows.
    private(set) var problem: SpectrumError?

    /// The profile's settings and the host's volume and mute, which the running measurement reads for every cycle.
    @ObservationIgnored let inputs = SpectrumInputs()
    @ObservationIgnored private let source: any SpectrumSource

    /// - Parameter source: Where the levels come from, a Core Audio tap on the SoundBox unless a test passes its own.
    init(source: (any SpectrumSource)? = nil) {
        self.source = source ?? CoreAudioSpectrumSource()
    }
}

extension SpectrumMonitor {
    /// The USB serial of the board whose spectrum the display shows: the verified board's while the display shows the
    /// spectrum, and nil otherwise, which stops the measurement.
    static func serial(showsSpectrum: Bool, board: BoardConnectionState) -> String? {
        guard
            showsSpectrum,
            case let .verified(capabilities) = board
        else {
            return nil
        }
        return capabilities.serial
    }

    /// Hands the profile's settings and the host's volume and mute to the measurement, which takes them with its next
    /// cycle, whether it runs already or starts later.
    func update(_ values: SpectrumInputs.Values) {
        inputs.current = values
    }

    /// Shows the levels of the SoundBox with USB serial `serial` until the calling task is cancelled, and silence for a
    /// nil serial, which stands for no verified board or a released key.
    func follow(serial: String?) async {
        levels = .silent
        problem = nil
        guard let serial else {
            return
        }
        do {
            for await measured in try await source.levels(serial: serial, inputs: inputs) {
                levels = measured
            }
        } catch let error as SpectrumError {
            problem = error
        } catch {
            problem = .captureFailed(error.localizedDescription)
        }
    }
}
