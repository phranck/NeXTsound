import Foundation
import NeXTsoundDSP
import NeXTsoundProtocol

/// The SoundBox's processing chain on the Mac, run by the same C engine as the firmware: the average of both channels,
/// the high-pass, the five EQ bands, the attenuation, the limiter and mute.
///
/// It starts muted, as the board does, and crossfades into new settings over `NXS_DSP_TRANSITION_FRAMES` frames.
/// `apply(_:)` refuses a second change while a crossfade runs, so the caller offers it again with the next block, as the
/// firmware's audio owner does.
public struct DSPEngine: Sendable {
    /// The most frames the C engine processes in one call.
    public static let blockFrames = Int(NXS_DSP_BLOCK_FRAMES)

    private var engine = nxs_dsp_t()

    /// A muted engine that crossfades into `settings` from its first frames on.
    ///
    /// - Throws: `WireError` for settings outside the protocol's bounds.
    public init(settings: DSPSettings) throws {
        nxs_dsp_init(&engine)
        var configuration = try settings.dspConfiguration()
        nxs_dsp_apply(&engine, &configuration)
    }
}

public extension DSPEngine {
    /// Starts the crossfade into `settings`, and returns false while the previous crossfade still runs.
    ///
    /// - Throws: `WireError` for settings outside the protocol's bounds.
    mutating func apply(_ settings: DSPSettings) throws -> Bool {
        var configuration = try settings.dspConfiguration()
        return nxs_dsp_apply(&engine, &configuration)
    }

    /// Processes `stereo`, interleaved left and right samples, into one mono sample per frame in `mono`, block by
    /// block. `mono` keeps its storage.
    ///
    /// - Returns: False when the engine refused a block, which leaves `mono` holding silence from that block on.
    mutating func process(_ stereo: [Float], into mono: inout [Float]) -> Bool {
        let frames = stereo.count / 2
        mono.removeAll(keepingCapacity: true)
        mono.append(contentsOf: repeatElement(0, count: frames))
        return stereo.withUnsafeBufferPointer { input in
            mono.withUnsafeMutableBufferPointer { output in
                var start = 0
                while start < frames {
                    let count = min(Self.blockFrames, frames - start)
                    guard
                        let inputBase = input.baseAddress,
                        let outputBase = output.baseAddress,
                        nxs_dsp_process(&engine, inputBase + 2 * start, outputBase + start, count)
                    else {
                        return false
                    }
                    start += count
                }
                return true
            }
        }
    }
}

extension DSPSettings {
    /// The C engine's configuration for these settings, the coefficients the firmware computes from the same values.
    ///
    /// - Throws: `WireError` for settings outside the protocol's bounds.
    func dspConfiguration() throws -> nxs_dsp_configuration_t {
        var snapshot = try protocolSnapshot(profileID: UUID(), revision: 0)
        var configuration = nxs_dsp_configuration_t()
        guard nxs_dsp_prepare(&snapshot, &configuration) else {
            throw WireError(result: NXS_RESULT_INVALID_PARAMETERS)
        }
        return configuration
    }
}
