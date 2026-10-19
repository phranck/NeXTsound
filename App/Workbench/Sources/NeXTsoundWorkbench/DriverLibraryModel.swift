import Foundation
import NeXTsoundCore
import Observation

/// Owner-maintained CRUD state for the driver model library. Holds no reference to
/// `BoardMonitor` or any board transport: adding, editing, selecting, or removing a driver
/// model never writes to a connected board.
@MainActor
@Observable
public final class DriverLibraryModel {
    public private(set) var library: DriverLibrary
    public private(set) var isReady: Bool
    public var errorMessage: String?

    @ObservationIgnored private let storage: (any DriverLibraryStorage)?
    @ObservationIgnored private var hasStarted = false

    public var drivers: [DriverRecord] {
        library.drivers
    }

    public init(library: DriverLibrary = DriverLibrary(), storage: (any DriverLibraryStorage)? = nil) {
        self.library = library
        self.storage = storage
        isReady = storage == nil
    }
}

public extension DriverLibraryModel {
    /// Loads the local library once. A failed load never blocks editing; it is surfaced
    /// through `errorMessage` while edits stay in memory until storage recovers.
    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        defer { isReady = true }
        guard let storage else {
            return
        }
        do {
            library = try await storage.load() ?? library
            try await storage.save(library)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addDriver() {
        perform { try $0.insert(DriverRecord(name: "New driver model")) }
    }

    func updateDriver(_ driver: DriverRecord) {
        perform { try $0.update(driver) }
    }

    func removeDriver(_ identifier: UUID) {
        perform { try $0.remove(identifier) }
    }
}

private extension DriverLibraryModel {
    func perform(mutation: (inout DriverLibrary) throws -> Void) {
        guard isReady else {
            return
        }
        do {
            var candidate = library
            try mutation(&candidate)
            library = candidate
            errorMessage = nil
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        guard let storage else {
            return
        }
        let snapshot = library
        Task {
            do {
                try await storage.save(snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
