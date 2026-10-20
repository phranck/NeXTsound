import AppKit
import NeXTsoundCore
import Observation

@MainActor
@Observable
public final class WorkbenchModel {
    public private(set) var library: ProfileLibrary
    public private(set) var isReady: Bool
    public private(set) var storageError: String?
    public var errorMessage: String?
    public var isImporting = false
    public var isExporting = false
    public let boards: BoardMonitor

    @ObservationIgnored private let storage: (any ProfileLibraryStorage)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    private var savedRevision: UInt64 = 0

    public var profile: SoundProfile {
        library.selectedProfile
    }

    /// Volatile DSP-only capture slots for A/B comparison. Never serialized, never part of the
    /// profile library, and capturing one never advances the library revision.
    public private(set) var slotA: DSPSettings?
    public private(set) var slotB: DSPSettings?

    public var storageStatus: String {
        if !isReady {
            return String(localized: "Loading profiles…")
        }
        if let storageError {
            return String(localized: "Changes are not saved. \(storageError)")
        }
        if storage == nil {
            return String(localized: "Temporary profile session")
        }
        return savedRevision == library.revision
            ? String(localized: "Profiles saved on this Mac")
            : String(localized: "Saving profiles…")
    }

    public init(library: ProfileLibrary = ProfileLibrary(), storage: (any ProfileLibraryStorage)? = nil, boards: BoardMonitor? = nil) {
        self.library = library
        self.storage = storage
        self.boards = boards ?? BoardMonitor(isEnabled: false)
        isReady = storage == nil
    }
}

public extension WorkbenchModel {
    /// Loads the local library once. A failed load never blocks editing or quitting; it is
    /// surfaced through `storageStatus` and local edits stay in memory until storage recovers.
    func start() async {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        boards.start()
        defer { isReady = true }
        guard let storage else {
            return
        }
        do {
            library = try await storage.load() ?? library
            try await storage.save(library)
            savedRevision = library.revision
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    func flush() async throws {
        guard let storage else {
            return
        }
        guard isReady else {
            throw ProfileLibraryError.invalidLibrary
        }
        saveTask?.cancel()
        let snapshot = library
        try await storage.save(snapshot)
        savedRevision = max(savedRevision, snapshot.revision)
        storageError = nil
    }

    func selectProfile(_ identifier: UUID) {
        perform { try $0.select(identifier) }
    }

    func updateProfile(_ proposed: SoundProfile, undoManager: UndoManager? = nil) {
        perform(undoManager: undoManager, action: "Edit profile") { try $0.updateSelected(proposed) }
    }

    func applyPreset(_ preset: FactoryPreset, undoManager: UndoManager? = nil) {
        perform(undoManager: undoManager, action: "Apply preset") { try $0.apply(preset) }
    }

    func addProfile(undoManager: UndoManager? = nil) {
        perform(undoManager: undoManager, action: "New profile") { try $0.insert(SoundProfile(name: "New profile")) }
    }

    func removeProfile(undoManager: UndoManager? = nil) {
        perform(undoManager: undoManager, action: "Delete profile") { try $0.removeSelected() }
    }

    func importProfile(at url: URL, undoManager: UndoManager? = nil) async {
        do {
            let imported = try await Task.detached { try ProfileLibraryStore.importedProfile(at: url) }.value
            perform(undoManager: undoManager, action: "Import profile") { try $0.insert(imported) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes a new persisted name to the connected SoundBox. The new name is visible to macOS
    /// only after the board next resets or is replugged.
    func renameBoard(_ name: String) async {
        do {
            try await boards.setDeviceName(name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Applies the current profile's DSP settings to the connected SoundBox for live listening,
    /// exactly as edited. Never writes to flash, so a reconnect or power cycle reverts to the
    /// last persisted state.
    func applyToBoard() async {
        do {
            let snapshot = DeviceSnapshot(profileID: profile.id, profileRevision: profile.revision, settings: profile.settings)
            try await boards.apply(snapshot)
        } catch is CancellationError {
            // Superseded by a newer edit; scheduleBoardApply() already queued the latest state.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Captures the current profile's DSP settings into slot A, overwriting whatever was there.
    func captureSlotA() {
        slotA = profile.settings
    }

    /// Captures the current profile's DSP settings into slot B, overwriting whatever was there.
    func captureSlotB() {
        slotB = profile.settings
    }

    /// Recalls slot A's DSP settings into the current profile through the normal edit
    /// transaction, so it advances the revision and supports undo like any other edit. A no-op
    /// if nothing was captured yet.
    func recallSlotA(undoManager: UndoManager? = nil) {
        guard let slotA else {
            return
        }
        recall(slotA, action: "Recall A", undoManager: undoManager)
    }

    /// Recalls slot B's DSP settings into the current profile. See `recallSlotA(undoManager:)`.
    func recallSlotB(undoManager: UndoManager? = nil) {
        guard let slotB else {
            return
        }
        recall(slotB, action: "Recall B", undoManager: undoManager)
    }
}

private extension WorkbenchModel {
    func perform(undoManager: UndoManager? = nil, action: String = "Change profile", mutation: (inout ProfileLibrary) throws -> Void) {
        guard isReady else {
            return
        }
        do {
            let previous = library
            var candidate = previous
            try mutation(&candidate)
            guard candidate != previous else {
                return
            }
            library = candidate
            registerUndo(previous, manager: undoManager, action: action)
            scheduleSave()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Replaces only the current profile's DSP settings through the normal edit transaction,
    /// keeping identity, name, speaker, and enclosure exactly as they were.
    func recall(_ settings: DSPSettings, action: String, undoManager: UndoManager?) {
        var proposed = profile
        proposed.settings = settings
        perform(undoManager: undoManager, action: action) { try $0.updateSelected(proposed) }
    }

    func registerUndo(_ previous: ProfileLibrary, manager: UndoManager?, action: String) {
        guard let manager else {
            return
        }
        manager.registerUndo(withTarget: self) { [weak manager] target in
            target.perform(undoManager: manager, action: action) { try $0.restoreContents(from: previous) }
        }
        manager.setActionName(action)
    }

    func scheduleSave() {
        guard let storage else {
            return
        }
        saveTask?.cancel()
        let snapshot = library
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await storage.save(snapshot)
                guard
                    let self,
                    !Task.isCancelled
                else {
                    return
                }
                savedRevision = max(savedRevision, snapshot.revision)
                if library.revision == snapshot.revision {
                    storageError = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard
                    let self,
                    !Task.isCancelled
                else {
                    return
                }
                storageError = error.localizedDescription
            }
        }
    }
}
