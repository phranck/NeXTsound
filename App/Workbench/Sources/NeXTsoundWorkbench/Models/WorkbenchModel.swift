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
    /// True from the moment a save to the SoundBox is requested until its flash write finished or failed.
    public private(set) var isSavingToBoard = false
    public let boards: BoardMonitor
    /// The serial numbers the app has written to boards. Empty until `start()` reads it.
    public private(set) var serialNumbers = SerialNumberRegister()
    /// Whether the register was read, or there is no store to read it from. While it is false, the edit form refuses
    /// to give a board a number, because the number could already belong to another board.
    public private(set) var serialNumbersAreAvailable: Bool
    /// The newer release found by the one automatic check in this app session.
    public private(set) var availableFirmwareUpdate: FirmwareRelease?

    @ObservationIgnored private let storage: (any ProfileLibraryStorage)?
    @ObservationIgnored private let serialNumberStorage: (any SerialNumberRegisterStorage)?
    @ObservationIgnored private let firmwareReleaseService: (any FirmwareReleaseService)?
    @ObservationIgnored private var hasCheckedForFirmwareUpdates = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var boardApplyTask: Task<Void, Never>?
    @ObservationIgnored private var isWritingToBoard = false
    @ObservationIgnored private var boardApplyIsPending = false
    @ObservationIgnored private var boardSaveIsPending = false
    @ObservationIgnored private var startTask: Task<Void, Never>?
    private var savedRevision: UInt64 = 0

    public var profile: SoundProfile {
        library.selectedProfile
    }

    /// Volatile DSP-only capture slots for A/B comparison. Never serialized, never part of the
    /// profile library, and capturing one never advances the library revision.
    public private(set) var slotA: DSPSettings?
    public private(set) var slotB: DSPSettings?

    /// Nil once the library is loaded, unchanged, and persisted: nothing to report. Surfaces
    /// loading, a save in progress, a storage error, or a non-persistent session otherwise.
    public var storageStatus: String? {
        if !isReady {
            return String(localized: "Loading profiles…")
        }
        if let storageError {
            return String(localized: "Changes are not saved. \(storageError)")
        }
        if storage == nil {
            return String(localized: "Temporary profile session")
        }
        return savedRevision == library.revision ? nil : String(localized: "Saving profiles…")
    }

    /// Says whether the connected SoundBox starts with the settings it plays. Nil while no board is
    /// verified or its storage state is unknown.
    public var boardStorageStatus: String? {
        guard case .verified = boards.state else {
            return nil
        }
        if isSavingToBoard {
            return String(localized: "Saving to the SoundBox…")
        }
        switch boards.storage {
        case .unknown: return nil
        case .saved: return String(localized: "Settings saved on the SoundBox")
        case .unsaved: return String(localized: "Settings not saved on the SoundBox")
        case .unavailable: return String(localized: "This SoundBox cannot save settings")
        }
    }

    /// True while a verified board with usable storage is connected and no save is running.
    public var canSaveToBoard: Bool {
        guard case .verified = boards.state else {
            return false
        }
        return boards.storage != .unavailable && !isSavingToBoard
    }

    public init(
        library: ProfileLibrary = ProfileLibrary(),
        storage: (any ProfileLibraryStorage)? = nil,
        boards: BoardMonitor? = nil,
        serialNumberStorage: (any SerialNumberRegisterStorage)? = nil,
        firmwareReleaseService: (any FirmwareReleaseService)? = nil
    ) {
        self.library = library
        self.storage = storage
        self.boards = boards ?? BoardMonitor(isEnabled: false)
        self.serialNumberStorage = serialNumberStorage
        self.firmwareReleaseService = firmwareReleaseService
        isReady = storage == nil
        serialNumbersAreAvailable = serialNumberStorage == nil
        self.boards.onMetadataRead = { [weak self] chip, metadata in
            self?.adoptSerialNumber(metadata.serialNumber, from: chip)
        }
        self.boards.onVerified = { [weak self] _ in
            self?.checkForFirmwareUpdatesIfNeeded()
        }
    }
}

public extension WorkbenchModel {
    /// Loads the local library once. A failed load never blocks editing or quitting; it is
    /// surfaced through `storageStatus` and local edits stay in memory until storage recovers.
    /// Every later call waits for that one load to finish, so a caller that needs the loaded library calls it too.
    func start() async {
        if startTask == nil {
            startTask = Task { await loadLibrary() }
        }
        await startTask?.value
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

    func addProfile(undoManager: UndoManager? = nil) {
        perform(undoManager: undoManager, action: "New profile") { try $0.insert(SoundProfile(name: "New profile")) }
    }

    func removeProfile(undoManager: UndoManager? = nil) {
        perform(undoManager: undoManager, action: "Delete profile") { try $0.removeSelected() }
    }

    /// Sets the current profile's speaker to a snapshot of the given driver, or clears it, through
    /// the normal edit transaction, so it advances the revision and supports undo like any other
    /// edit. The driver library itself is never referenced live; see `SpeakerRecord.init(driver:)`.
    ///
    /// When the driver's Fs, Qts, and Vas are all known, this also sets the electronic high-pass
    /// to the resulting closed-box corner frequency against the one fixed enclosure
    /// (`EnclosureRecord.nextSoundBoxMini()`) and enables it, and sets band 1 to
    /// `ClosedBoxAlignment.correctionGainDb` at that same frequency with quality equal to the
    /// alignment's own Qtc, canceling the box's own magnitude deviation from flat at its corner:
    /// a physically grounded starting point for the box this product actually ships, not a
    /// measurement. Both figures are clamped to the firmware's own parameter bounds, since they
    /// are a continuous physical quantity fit to a hardware-constrained control, not invented. A
    /// driver missing any of the three values leaves the high-pass and that band exactly as they
    /// were; no missing input is guessed. This is the one part of #19's planned calculation that
    /// needs no data beyond what the driver library and the fixed enclosure already carry.
    /// Attenuation, the remaining EQ bands, and the limiter stay untouched: setting any of them
    /// to a specific physical limit needs the amplifier/supply voltage transfer this project does
    /// not have yet.
    func selectSpeaker(_ driver: DriverRecord?, undoManager: UndoManager? = nil) {
        var proposed = profile
        proposed.speaker = driver.map(SpeakerRecord.init(driver:))
        if let driver, let alignment = try? ClosedBoxAlignment(driver: driver, enclosure: .nextSoundBoxMini()) {
            let frequencyHz = Float(alignment.cornerFrequencyHz)
            proposed.settings.highPassEnabled = true
            proposed.settings.highPassHz = frequencyHz
            let gainBounds = DSPParameter.bandGain.bounds
            let qualityBounds = DSPParameter.bandQuality.bounds
            let gainDb = min(max(Float(alignment.correctionGainDb), gainBounds.lowerBound), gainBounds.upperBound)
            let quality = min(max(Float(alignment.totalQ), qualityBounds.lowerBound), qualityBounds.upperBound)
            proposed.settings.bands[0] = EQBand(frequencyHz: frequencyHz, gainDb: gainDb, quality: quality, isEnabled: true)
        }
        perform(undoManager: undoManager, action: "Select speaker") { try $0.updateSelected(proposed) }
    }

    func importProfile(at url: URL, undoManager: UndoManager? = nil) async {
        do {
            let imported = try await Task.detached { try ProfileLibraryStore.importedProfile(at: url) }.value
            perform(undoManager: undoManager, action: "Import profile") { try $0.insert(imported) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Imports a profile file macOS asked the app to open, such as one double-clicked in the Finder, and selects it, so
    /// it plays on a connected board. A file that launches the app arrives before the stored library has loaded, and
    /// the load replaces the library, so the import waits for `start()` first.
    func openProfile(at url: URL) async {
        await start()
        await importProfile(at: url)
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

    /// Writes what the edit form changed to the connected SoundBox: the name, and the owner metadata. A written serial
    /// number goes into the register, and a cleared one is removed from it, so the next proposal knows about both.
    func editBoard(name: String, metadata: OwnerMetadata) async {
        guard let capabilities = boards.state.verifiedCapabilities else {
            return
        }
        do {
            if name != capabilities.deviceName {
                try await boards.setDeviceName(name)
            }
            if metadata != boards.metadata {
                try await boards.writeMetadata(metadata)
                serialNumbers.assign(metadata.serialNumber, to: capabilities.serial)
                await saveSerialNumbers()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Applies the current profile's DSP settings to the connected SoundBox for live listening,
    /// exactly as edited. Never writes to flash, so a reconnect or power cycle reverts to the
    /// last persisted state.
    ///
    /// At most one write is ever in flight against the transport. An edit that arrives while a
    /// write is already running only marks a follow-up as pending instead of starting a second,
    /// independent call: the transport serializes every board exchange on one queue, so a second
    /// call would queue up behind the first and its own timeout clock would already be ticking
    /// before it ever reaches the wire.
    func applyToBoard() async {
        await writeToBoard()
    }

    /// Applies the current profile to the connected SoundBox and then saves it to the board's flash,
    /// so the board starts with what it plays after the next power-up. A save requested while a
    /// write is in flight runs right after it, through the same single write as `applyToBoard()`.
    func saveToBoard() async {
        guard canSaveToBoard else {
            return
        }
        isSavingToBoard = true
        boardSaveIsPending = true
        await writeToBoard()
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
    /// Runs one edit of the library. Its outcome replaces the last action's error, because the front panel shows the
    /// error in its display until something newer takes its place.
    func perform(undoManager: UndoManager? = nil, action: String = "Change profile", mutation: (inout ProfileLibrary) throws -> Void) {
        guard isReady else {
            return
        }
        errorMessage = nil
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
            scheduleBoardApply()
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

    /// The one board write in flight. Each pass applies the current profile, and persists it when a
    /// save was requested, until no apply or save is pending any more.
    func writeToBoard() async {
        guard case .verified = boards.state else {
            return
        }
        guard !isWritingToBoard else {
            boardApplyIsPending = true
            return
        }
        isWritingToBoard = true
        defer { isWritingToBoard = false }
        repeat {
            boardApplyIsPending = false
            let saves = boardSaveIsPending
            boardSaveIsPending = false
            do {
                let snapshot = DeviceSnapshot(profileID: profile.id, profileRevision: profile.revision, settings: profile.settings)
                try await boards.apply(snapshot)
                if saves {
                    try await boards.persist()
                }
            } catch is CancellationError {
                // Superseded by a newer edit; scheduleBoardApply() already queued the latest state.
                // A save cancelled with it ends without an error; saving again writes the latest state.
            } catch {
                errorMessage = error.localizedDescription
            }
            if saves, !boardSaveIsPending {
                isSavingToBoard = false
            }
        } while boardApplyIsPending || boardSaveIsPending
    }

    /// Mirrors the current profile to the connected board after edits settle, so the signal
    /// chain editor behaves like a live monitor rather than requiring a manual push. Debounced
    /// the same way as `scheduleSave()`, and a no-op whenever no board is verified.
    func scheduleBoardApply() {
        boardApplyTask?.cancel()
        boardApplyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            await self?.applyToBoard()
        }
    }

    /// The one load `start()` runs: the serial number register, then the boards, then the stored library.
    func loadLibrary() async {
        // Read before the boards connect, so the number a connected board carries reaches a loaded register.
        await loadSerialNumbers()
        boards.start()
        checkForFirmwareUpdatesIfNeeded()
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

    /// Checks once per app session when the first board verifies. A failed background request stays silent; the flash
    /// sheet keeps its own visible error and retry path, and no firmware is downloaded or flashed here.
    func checkForFirmwareUpdatesIfNeeded() {
        guard
            let firmwareReleaseService,
            !hasCheckedForFirmwareUpdates,
            let capabilities = boards.state.verifiedCapabilities,
            let currentVersion = FirmwareVersion(boardVersion: capabilities.firmwareVersion)
        else {
            return
        }
        hasCheckedForFirmwareUpdates = true
        Task {
            do {
                let release = try await firmwareReleaseService.latestRelease()
                guard
                    !Task.isCancelled,
                    boards.state.verifiedCapabilities?.serial == capabilities.serial,
                    release.version > currentVersion
                else {
                    return
                }
                availableFirmwareUpdate = release
            } catch {
                // The flash sheet reports its own errors when the owner asks for an update check there.
            }
        }
    }

    /// Reads the register once. A register that cannot be read stays unavailable, so no number is proposed against an
    /// empty one and no save replaces the file.
    func loadSerialNumbers() async {
        guard let serialNumberStorage else {
            return
        }
        do {
            serialNumbers = try await serialNumberStorage.load() ?? SerialNumberRegister()
            serialNumbersAreAvailable = true
        } catch {
            errorMessage = String(localized: "The serial-number register cannot be read. \(error.localizedDescription)")
        }
    }

    /// Takes over the number a connected board carries, unless the register already gives it to another board.
    func adoptSerialNumber(_ number: UInt32?, from chip: String) {
        guard
            let number,
            serialNumbersAreAvailable,
            serialNumbers.adopt(number, from: chip)
        else {
            return
        }
        Task { await saveSerialNumbers() }
    }

    func saveSerialNumbers() async {
        guard
            serialNumbersAreAvailable,
            let serialNumberStorage
        else {
            return
        }
        do {
            try await serialNumberStorage.save(serialNumbers)
        } catch {
            errorMessage = String(localized: "The serial-number register cannot be saved. \(error.localizedDescription)")
        }
    }
}
