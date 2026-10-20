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

    private(set) var outcome: Outcome = .idle
    let target: FlashTarget

    @ObservationIgnored private let service: FlashService?
    @ObservationIgnored private let firmwareURL: URL?

    init(target: FlashTarget, runner: (any PicotoolRunning)? = ProcessPicotoolRunner(), firmwareBundle: Bundle = .module) {
        self.target = target
        service = runner.map { FlashService(runner: $0) }
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

    func flash() {
        guard
            let service,
            let firmwareURL,
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
            } catch {
                outcome = .failed(error.localizedDescription)
            }
        }
    }
}
