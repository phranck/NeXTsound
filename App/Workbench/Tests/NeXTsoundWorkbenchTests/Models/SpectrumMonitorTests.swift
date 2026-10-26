import Foundation
import NeXTsoundCore
import Synchronization
import Testing
@testable import NeXTsoundWorkbench

@MainActor
struct SpectrumMonitorTests {
    /// The monitor shows the latest levels its source measures for the board it follows, and its task's cancellation
    /// ends the source's measurement.
    @Test func theMonitorShowsTheLevelsOfTheBoardItFollows() async throws {
        let loud = SpectrumLevels(decibels: SpectrumLevels.silent.decibels.map { _ in -6 })
        let source = FakeSpectrumSource(levels: [Self.quiet, loud])
        let monitor = SpectrumMonitor(source: source)
        let task = Task { await monitor.follow(serial: "D4CDD489AFE28CC5") }
        try await Self.waitUntil { monitor.levels == loud }
        task.cancel()
        await task.value
        #expect(source.requestedSerials == ["D4CDD489AFE28CC5"])
        try await Self.waitUntil { source.isTerminated }
        #expect(monitor.problem == nil)
    }

    /// Without a board to follow, the monitor shows silence and starts no measurement.
    @Test func withoutABoardTheMonitorShowsSilence() async {
        let source = FakeSpectrumSource(levels: [Self.quiet])
        let monitor = SpectrumMonitor(source: source)
        await monitor.follow(serial: nil)
        #expect(monitor.levels == .silent)
        #expect(source.requestedSerials.isEmpty)
    }

    /// A measurement that cannot start shows its reason on the message card while it waits to try again, and the next
    /// start clears it.
    @Test func aFailedStartShowsItsReasonWhileItWaits() async throws {
        let source = FakeSpectrumSource(levels: [], failures: [.unsupportedAudioFormat])
        let monitor = SpectrumMonitor(source: source, retryInterval: .seconds(60))
        let task = Task { await monitor.follow(serial: "D4CDD489AFE28CC5") }
        try await Self.waitUntil { monitor.problem == .unsupportedAudioFormat }
        #expect(monitor.levels == .silent)
        #expect(source.requestedSerials == ["D4CDD489AFE28CC5"])
        task.cancel()
        await task.value
        await monitor.follow(serial: nil)
        #expect(monitor.problem == nil)
    }

    /// A board that reconnects verifies before Core Audio lets the app record its output, so a measurement that cannot
    /// start tries again until it runs, and the running measurement clears the last reason.
    @Test func aFailedStartIsTriedAgainUntilTheMeasurementRuns() async throws {
        let source = FakeSpectrumSource(levels: [Self.quiet], failures: [.soundBoxAudioNotFound, .captureFailed("Not ready")])
        let monitor = SpectrumMonitor(source: source, retryInterval: .milliseconds(10))
        let task = Task { await monitor.follow(serial: "D4CDD489AFE28CC5") }
        try await Self.waitUntil { monitor.levels == Self.quiet }
        #expect(monitor.problem == nil)
        #expect(source.requestedSerials == Array(repeating: "D4CDD489AFE28CC5", count: 3))
        task.cancel()
        await task.value
    }

    /// The display measures the verified board while it shows the spectrum, and nothing while it shows the curve or no
    /// board is verified.
    @Test func onlyAVerifiedBoardIsMeasuredWhileTheSpectrumShows() {
        let verified = BoardConnectionState.verified(DeviceCapabilities(serial: "D4CDD489AFE28CC5", firmwareVersion: "0.2.0"))
        #expect(SpectrumMonitor.serial(showsSpectrum: true, board: verified) == "D4CDD489AFE28CC5")
        #expect(SpectrumMonitor.serial(showsSpectrum: false, board: verified) == nil)
        #expect(SpectrumMonitor.serial(showsSpectrum: true, board: .detected) == nil)
        #expect(SpectrumMonitor.serial(showsSpectrum: true, board: .mismatched("The serial does not match.")) == nil)
    }

    /// The measurement reads the inputs the monitor holds, so an update after its start still reaches it.
    @Test func anUpdateReachesARunningMeasurement() async throws {
        let source = FakeSpectrumSource(levels: [Self.quiet])
        let monitor = SpectrumMonitor(source: source)
        let task = Task { await monitor.follow(serial: "D4CDD489AFE28CC5") }
        try await Self.waitUntil { monitor.levels == Self.quiet }
        var values = monitor.inputs.current
        values.hostVolumeDb = -18
        monitor.update(values)
        #expect(source.inputs?.current.hostVolumeDb == -18)
        task.cancel()
        await task.value
    }
}

private extension SpectrumMonitorTests {
    static let quiet = SpectrumLevels(decibels: SpectrumLevels.silent.decibels.map { _ in -40 })

    /// Waits for `condition` on the main actor, for at most a second.
    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

/// A source that hands out fixed levels after refusing its first starts, and records what it was asked for.
private final class FakeSpectrumSource: SpectrumSource {
    private let levels: [SpectrumLevels]
    private let state: Mutex<State>

    /// - Parameters:
    ///   - levels: The levels every start that succeeds hands out.
    ///   - failures: The errors the first starts throw, one per start, before the starts succeed.
    init(levels: [SpectrumLevels], failures: [SpectrumError] = []) {
        self.levels = levels
        state = Mutex(State(failures: failures))
    }

    var requestedSerials: [String] {
        state.withLock(\.requestedSerials)
    }

    var isTerminated: Bool {
        state.withLock(\.isTerminated)
    }

    /// The inputs the last measurement was started with.
    var inputs: SpectrumInputs? {
        state.withLock(\.inputs)
    }

    func levels(serial: String, inputs: SpectrumInputs) async throws -> AsyncStream<SpectrumLevels> {
        let failure = state.withLock { state -> SpectrumError? in
            state.requestedSerials.append(serial)
            state.inputs = inputs
            return state.failures.isEmpty ? nil : state.failures.removeFirst()
        }
        if let failure {
            throw failure
        }
        let (stream, continuation) = AsyncStream.makeStream(of: SpectrumLevels.self)
        for level in levels {
            continuation.yield(level)
        }
        continuation.onTermination = { _ in
            self.state.withLock { $0.isTerminated = true }
        }
        return stream
    }
}

private extension FakeSpectrumSource {
    struct State {
        var requestedSerials: [String] = []
        var inputs: SpectrumInputs?
        var isTerminated = false
        var failures: [SpectrumError] = []
    }
}
