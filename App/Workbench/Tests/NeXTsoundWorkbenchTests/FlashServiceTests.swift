import Foundation
import Testing
@testable import NeXTsoundWorkbench

struct FlashServiceTests {
    @Test func aKnownSerialForcesTheConnectedBoardStraightIntoTheLoadCommand() async throws {
        let runner = FakePicotoolRunner()
        let service = FlashService(runner: runner)
        let recorder = FlashPhaseRecorder()
        try await service
            .flash(URL(fileURLWithPath: "/tmp/firmware.uf2"), target: FlashTarget(applicationSerial: "ABC123")) { recorder.record($0) }

        #expect(recorder.phases == [.writingAndVerifying, .restartingApplication])
        #expect(runner.invocations.count == 2)
        #expect(runner.invocations[0] == ["load", "-v", "-F", "--vid", "0xcafe", "--pid", "0x4014", "--ser", "ABC123", "/tmp/firmware.uf2"])
        #expect(runner.invocations[1] == ["reboot", "--ser", "ABC123"])
    }

    @Test func noKnownSerialWaitsForTheBoardByTheFixedBootselIdentity() async throws {
        let runner = FakePicotoolRunner()
        runner.infoAttemptsBeforeSuccess = 2
        let service = FlashService(runner: runner, pollInterval: .milliseconds(1))
        let recorder = FlashPhaseRecorder()
        try await service.flash(URL(fileURLWithPath: "/tmp/firmware.uf2"), target: FlashTarget()) { recorder.record($0) }

        #expect(recorder.phases == [.waitingForBootloader, .writingAndVerifying, .restartingApplication])
        #expect(runner.invocations.filter { $0.first == "info" }.count == 3)
        #expect(runner.invocations.last(where: { $0.first == "load" }) ==
            ["load", "-v", "--vid", "0x2e8a", "--pid", "0xf", "/tmp/firmware.uf2"])
        #expect(runner.invocations.last == ["reboot", "--vid", "0x2e8a", "--pid", "0xf"])
    }

    @Test func aFailedWriteNeverReboots() async {
        let runner = FakePicotoolRunner()
        runner.exitCodeByCommand["load"] = 1
        runner.outputByCommand["load"] = "ERROR: verification failed"
        let service = FlashService(runner: runner)

        await #expect(throws: FlashError.commandFailed(.writingAndVerifying, "ERROR: verification failed")) {
            try await service.flash(URL(fileURLWithPath: "/tmp/firmware.uf2"), target: FlashTarget(applicationSerial: "ABC123")) { _ in }
        }
        #expect(runner.invocations.allSatisfy { $0.first != "reboot" })
    }

    @Test func theBoardNeverAppearingInBootselTimesOut() async {
        let runner = FakePicotoolRunner()
        runner.infoAttemptsBeforeSuccess = .max
        let service = FlashService(runner: runner, pollInterval: .milliseconds(1), bootloaderTimeout: .milliseconds(10))

        await #expect(throws: FlashError.timedOut(.waitingForBootloader)) {
            try await service.flash(URL(fileURLWithPath: "/tmp/firmware.uf2"), target: FlashTarget()) { _ in }
        }
        #expect(runner.invocations.allSatisfy { $0.first == "info" })
    }
}
