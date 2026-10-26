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
    /// A measurement that cannot start for a reason other than a missing output leaves that reason for the message card,
    /// and the next start clears it.
    @Test func aFailedStartLeavesItsReasonUntilTheNextStart() async {
        let source = FakeSpectrumSource(levels: [], failures: [.unsupportedAudioFormat])
        let monitor = SpectrumMonitor(source: source)
        await monitor.follow(serial: "D4CDD489AFE28CC5")
        #expect(monitor.problem == .unsupportedAudioFormat)
        #expect(monitor.levels == .silent)
        await monitor.follow(serial: nil)
        #expect(monitor.problem == nil)
    }

    /// A board that verifies before macOS lists its audio output gets its spectrum once the device list changes, and the
    /// message card shows the missing output until then.
    @Test func aMissingOutputIsTriedAgainWhenTheDeviceListChanges() async throws {
        let source = FakeSpectrumSource(levels: [Self.quiet], failures: [.soundBoxAudioNotFound])
        let monitor = SpectrumMonitor(source: source)
        let task = Task { await monitor.follow(serial: "D4CDD489AFE28CC5") }
        try await Self.waitUntil { monitor.problem == .soundBoxAudioNotFound }
        source.changeDeviceList()
        try await Self.waitUntil { monitor.levels == Self.quiet }
        #expect(monitor.problem == nil)
        #expect(source.requestedSerials == ["D4CDD489AFE28CC5", "D4CDD489AFE28CC5"])
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

/// A source that hands out fixed levels, or refuses to start, and records what it was asked for.
/// A source that hands out fixed levels after refusing its first starts, records what it was asked for, and reports a
/// change of macOS's device list when a test asks it to.
private final class FakeSpectrumSource: SpectrumSource {
    private let levels: [SpectrumLevels]
    private let state: Mutex<State>
    private let deviceList = AsyncStream.makeStream(of: Void.self)

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

    /// Reports a change of macOS's device list to the monitor that listens.
    func changeDeviceList() {
        deviceList.continuation.yield()
    }

    func audioDeviceListChanges() -> AsyncStream<Void> {
        deviceList.stream
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
