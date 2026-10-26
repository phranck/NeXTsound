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

    /// A measurement that cannot start leaves its reason for the message card, and the next start clears it.
    @Test func aFailedStartLeavesItsReasonUntilTheNextStart() async {
        let source = FakeSpectrumSource(levels: [], failure: .soundBoxAudioNotFound)
        let monitor = SpectrumMonitor(source: source)
        await monitor.follow(serial: "D4CDD489AFE28CC5")
        #expect(monitor.problem == .soundBoxAudioNotFound)
        #expect(monitor.levels == .silent)
        await monitor.follow(serial: nil)
        #expect(monitor.problem == nil)
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

/// A source that hands out fixed levels, or refuses to start, and records what it was asked for.
private final class FakeSpectrumSource: SpectrumSource {
    private let levels: [SpectrumLevels]
    private let failure: SpectrumError?
    private let state = Mutex(State())

    init(levels: [SpectrumLevels], failure: SpectrumError? = nil) {
        self.levels = levels
        self.failure = failure
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
        state.withLock {
            $0.requestedSerials.append(serial)
            $0.inputs = inputs
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
    }
}
