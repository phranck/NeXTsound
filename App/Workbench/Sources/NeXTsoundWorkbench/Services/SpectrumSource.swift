import Foundation

/// Where the live spectrum's levels come from: a Core Audio tap on the SoundBox's output, or a fake in tests.
protocol SpectrumSource: Sendable {
    /// Starts measuring the audio macOS sends to the SoundBox with USB serial `serial`, and returns the levels as the
    /// measurement produces them. Ending the iteration over the stream, or cancelling the task that iterates it, stops
    /// the measurement.
    ///
    /// - Throws: `SpectrumError` when the measurement cannot start.
    func levels(serial: String) async throws -> AsyncStream<SpectrumLevels>
}
