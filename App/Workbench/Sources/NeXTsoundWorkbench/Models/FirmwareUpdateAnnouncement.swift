extension WorkbenchModel {
    /// Dismisses the announced update after the owner clicks its VFD message. It does not trigger another check.
    public func dismissFirmwareUpdate() {
        availableFirmwareUpdate = nil
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
}
