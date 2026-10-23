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
    ///
    /// Merges in any known candidate driver (`DriverLibrary.knownCandidates`) not already
    /// present by id, so a library persisted before a new candidate was researched picks it up
    /// on the next launch rather than staying frozen at whatever it was first seeded with.
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
            mergeKnownCandidates()
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
    func mergeKnownCandidates() {
        let presentIDs = Set(library.drivers.map(\.id))
        for candidate in DriverLibrary.knownCandidates where !presentIDs.contains(candidate.id) {
            try? library.insert(candidate)
        }
    }

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
