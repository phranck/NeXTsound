import Foundation

/// Where the live spectrum's levels come from: a Core Audio tap on the SoundBox's output, or a fake in tests.
protocol SpectrumSource: Sendable {
    /// Starts measuring what the SoundBox with USB serial `serial` sends to its amplifier, and returns the levels as the
    /// measurement produces them. The measurement reads `inputs` for every cycle, so a change to them reaches the
    /// levels while it runs. Ending the iteration over the stream, or cancelling the task that iterates it, stops the
    /// measurement.
    ///
    /// - Throws: `SpectrumError` when the measurement cannot start.
    func levels(serial: String, inputs: SpectrumInputs) async throws -> AsyncStream<SpectrumLevels>
}
