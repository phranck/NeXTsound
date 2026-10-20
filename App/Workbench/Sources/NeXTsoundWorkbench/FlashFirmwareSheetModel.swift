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
    var selectedFirmwareURL: URL?
    let target: FlashTarget

    @ObservationIgnored private let service: FlashService?

    init(target: FlashTarget, runner: (any PicotoolRunning)? = ProcessPicotoolRunner()) {
        self.target = target
        if let runner {
            service = FlashService(runner: runner)
        } else {
            service = nil
            outcome = .failed(FlashError.picotoolUnavailable.errorDescription ?? "")
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
            let selectedFirmwareURL,
            !isRunning
        else {
            return
        }
        outcome = .running(.writingAndVerifying)
        Task {
            do {
                try await service.flash(selectedFirmwareURL, target: target) { [weak self] phase in
                    Task { @MainActor in self?.outcome = .running(phase) }
                }
                outcome = .succeeded
            } catch {
                outcome = .failed(error.localizedDescription)
            }
        }
    }
}
