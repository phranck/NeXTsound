import Foundation
import Observation

@MainActor
@Observable
final class FlashFirmwareSheetModel {
    enum Outcome: Equatable {
        case idle
        case running(FlashPhase)
        case succeeded
        case failed(String)
    }

    enum UpdateState: Equatable {
        case idle
        case checking
        case available(FirmwareRelease)
        case upToDate
        case failed(String)
    }

    private(set) var outcome: Outcome = .idle
    private(set) var updateState: UpdateState = .idle
    let target: FlashTarget

    @ObservationIgnored private let service: FlashService?
    @ObservationIgnored private let releaseService: any FirmwareReleaseService
    @ObservationIgnored private let firmwareURL: URL?

    init(
        target: FlashTarget,
        runner: (any PicotoolRunning)? = ProcessPicotoolRunner(),
        firmwareBundle: Bundle = .module,
        releaseService: (any FirmwareReleaseService)? = nil
    ) {
        self.target = target
        service = runner.map { FlashService(runner: $0) }
        self.releaseService = releaseService ?? GitHubFirmwareReleaseService()
        firmwareURL = firmwareBundle.url(forResource: "nxs_firmware", withExtension: "uf2")
        if service == nil {
            outcome = .failed(FlashError.picotoolUnavailable.errorDescription ?? "")
        } else if firmwareURL == nil {
            outcome = .failed(FlashError.firmwareUnavailable.errorDescription ?? "")
        }
    }
}

extension FlashFirmwareSheetModel {
    var isRunning: Bool {
        if case .running = outcome {
            return true
        }
        return false
    }

    /// Whether the owner holds the board into BOOTSEL by hand, because no verified board names the serial that
    /// `FlashService` reboots it by.
    var needsBootselByHand: Bool {
        target.applicationSerial == nil
    }

    /// Whether the sheet shows the board's restart, which it does once the firmware is written and verified.
    var showsRestartStatus: Bool {
        outcome == .succeeded
    }

    /// Whether Flash can start: not while a flash runs, and not again after one succeeded.
    var canFlash: Bool {
        !isRunning && outcome != .succeeded
    }

    /// Checks GitHub for a newer firmware than the connected board reports.
    func checkForUpdates() async {
        guard let versionString = target.applicationVersion else {
            updateState = .idle
            return
        }
        guard let currentVersion = FirmwareVersion(boardVersion: versionString) else {
            updateState = .failed(String(localized: "The board's firmware version cannot be read."))
            return
        }
        updateState = .checking
        do {
            let release = try await releaseService.latestRelease()
            updateState = release.version > currentVersion ? .available(release) : .upToDate
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    /// Dismisses the offer without downloading or changing the firmware.
    func declineUpdate() {
        if case .available = updateState {
            updateState = .idle
        }
    }

    /// Downloads the offered firmware and flashes it only after the user chose Update.
    func installUpdate() {
        guard case let .available(release) = updateState else {
            return
        }
        updateState = .checking
        Task {
            do {
                let firmwareURL = try await releaseService.download(release)
                flash(firmwareURL: firmwareURL)
            } catch {
                updateState = .failed(error.localizedDescription)
            }
        }
    }

    func flash() {
        guard let firmwareURL else {
            return
        }
        flash(firmwareURL: firmwareURL)
    }

    /// Flashes either the bundled firmware or one downloaded after explicit confirmation.
    private func flash(firmwareURL: URL) {
        guard
            let service,
            !isRunning
        else {
            return
        }
        outcome = .running(.writingAndVerifying)
        Task {
            do {
                try await service.flash(firmwareURL, target: target) { [weak self] phase in
                    Task { @MainActor in self?.outcome = .running(phase) }
                }
                outcome = .succeeded
                updateState = .upToDate
            } catch {
                outcome = .failed(error.localizedDescription)
                updateState = .failed(error.localizedDescription)
            }
        }
    }
}
