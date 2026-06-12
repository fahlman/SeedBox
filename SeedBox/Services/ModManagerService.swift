import Foundation

actor ModManagerService {
    let folderAccessCoordinator: ModManagerFolderAccessCoordinator
    let auditRecorder: ModManagerAuditRecorder
    let modSetDirectory: URL
    let stateStore: ModManagerStateStore
    let updateChecker: ModUpdateChecking
    /// Separate read-only grant for SMAPI's log folder, which lives outside
    /// the managed Mods folder.
    let smapiLogFolderAccess: SecurityScopedFolderAccess

    /// The canonical app state. Every mutation runs on this actor against the
    /// current value, so overlapping operations can never lose each other's
    /// updates.
    private(set) var state: ModManagerState

    init(
        folderAccess: SecurityScopedFolderAccess,
        smapiLogFolderAccess: SecurityScopedFolderAccess,
        stateStore: ModManagerStateStore,
        initialState: ModManagerState,
        modSetDirectory: URL = StardewInstall.defaultModSetDirectory(),
        auditLogURL: URL? = nil,
        updateChecker: ModUpdateChecking = SMAPIModUpdateClient()
    ) {
        folderAccessCoordinator = ModManagerFolderAccessCoordinator(folderAccess: folderAccess)
        self.smapiLogFolderAccess = smapiLogFolderAccess
        self.stateStore = stateStore
        state = initialState
        self.modSetDirectory = modSetDirectory
        let auditLogURL = auditLogURL ?? StardewInstall.auditLogURL(forModSetDirectory: modSetDirectory)
        auditRecorder = ModManagerAuditRecorder(logURL: auditLogURL)
        self.updateChecker = updateChecker
    }

    func commit(_ nextState: ModManagerState) -> ModManagerState {
        state = nextState
        stateStore.save(state)
        return state
    }

    func refreshedState(from state: ModManagerState) -> ModManagerState {
        var nextState = state
        nextState.hasSavedFolderAccess = folderAccessCoordinator.hasBookmark
        let install = install(for: nextState)

        if nextState.hasSavedFolderAccess {
            nextState.status = withFolderAccess(state: &nextState) {
                install.status()
            } ?? install.status()
        } else {
            nextState.status = install.status()
        }

        automaticallyPruneExpiredArchivedMods(in: &nextState)
        reloadMods(in: &nextState)
        reloadArchivedMods(in: &nextState)
        reloadModSets(in: &nextState)
        reloadAuditTrail(in: &nextState)
        reloadSMAPILogReport(in: &nextState)
        return nextState
    }

    func reconcileStartupModsFolderChange(
        from state: ModManagerState,
        previousModFolderTokens: Set<String>,
        appliedModSetID: String?
    ) -> ModManagerState {
        var refreshedState = refreshedState(from: state)
        let addedMods = addedMods(
            in: refreshedState,
            comparedTo: previousModFolderTokens
        )

        guard !addedMods.isEmpty else {
            return refreshedState
        }

        let selectedModSetID = refreshedState.selectedModSetID
        let appliedModSetID = appliedModSetID.flatMap { id in
            refreshedState.modSets.contains { $0.id == id } ? id : nil
        }

        if let appliedModSetID {
            setSelectedModSetID(appliedModSetID, in: &refreshedState)
            refreshedState.appliedModSetID = appliedModSetID
        }

        var reconciledState = reconcileAddedMods(
            addedMods,
            fallbackURLs: addedMods.map(\.url),
            source: .startupScan,
            shouldEnable: shouldEnableAddedMods(appliedModSetID: appliedModSetID),
            in: refreshedState
        )

        if reconciledState.modSets.contains(where: { $0.id == selectedModSetID }) {
            setSelectedModSetID(selectedModSetID, in: &reconciledState)
        }

        return reconciledState
    }

    func chooseModsFolder(_ selectedURL: URL, from state: ModManagerState) -> ModManagerState {
        var nextState = state
        let token = SecurityScopedAccessToken(url: selectedURL)
        defer {
            token.stop()
        }

        let resolvedURL = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedURL.lastPathComponent == StardewInstall.modFolderName else {
            record(AppStrings.Status.chooseFolderNamed(StardewInstall.modFolderName), in: &nextState)
            return nextState
        }

        do {
            try folderAccessCoordinator.saveBookmark(for: resolvedURL)
            nextState.hasSavedFolderAccess = folderAccessCoordinator.hasBookmark
            nextState.modsDirectoryPath = resolvedURL.path

            nextState = refreshedState(from: nextState)
            record(AppStrings.Status.selectedFolder(resolvedURL.path), in: &nextState)
            audit(
                .modsFolderSelected,
                summary: nextState.activityMessage,
                subjects: [auditSubjectForFolder(resolvedURL)],
                in: &nextState
            )
            return nextState
        } catch {
            record(AppStrings.Status.couldNotSaveFolderAccess(error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func createModFolder(from state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard nextState.hasSavedFolderAccess else {
            record(AppStrings.Status.chooseModsFolderBeforeCreating, in: &nextState)
            return nextState
        }

        do {
            let currentInstall = install(for: nextState)
            try performWithFolderAccess(state: &nextState) {
                try currentInstall.createModDirectory()
            }
            record(AppStrings.Status.createdModFolder(currentInstall.modDirectoryURL.path), in: &nextState)
            var refreshedState = refreshedState(from: nextState)
            audit(
                .modsFolderCreated,
                summary: refreshedState.activityMessage,
                subjects: [auditSubjectForFolder(currentInstall.modDirectoryURL)],
                in: &refreshedState
            )
            return refreshedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotCreateModFolder(error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func addMods(
        from selectedURLs: [URL],
        sourceCleanupSettings: SourceCleanupSettings,
        replacementPolicy: ModInstallReplacementPolicy = .newerOnly,
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        nextState.pendingSourceCleanupOffer = nil
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        guard !selectedURLs.isEmpty else {
            record(AppStrings.Status.chooseModFoldersOrZipArchives, in: &nextState)
            return nextState
        }

        let sourceTokens = selectedURLs.map(SecurityScopedAccessToken.init(url:))
        defer {
            sourceTokens.forEach { $0.stop() }
        }

        do {
            let currentInstall = install(for: nextState)
            let addedModsShouldBeEnabled = shouldEnableAddedMods(in: nextState)
            let installResult = try performWithFolderAccess(state: &nextState) {
                try ModLibrary.installMods(
                    from: selectedURLs,
                    into: currentInstall,
                    enabled: addedModsShouldBeEnabled,
                    replacementPolicy: replacementPolicy,
                    archiveDirectory: currentInstall.archivedModsDirectoryURL
                )
            }
            return reconcileInstallResult(
                installResult,
                source: .selectedSources(selectedURLs),
                shouldEnable: addedModsShouldBeEnabled,
                sourceCleanupSettings: sourceCleanupSettings,
                in: nextState
            )
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotAddMods(error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func addPreviewedMods(
        _ preview: ModImportPreview,
        sourceCleanupSettings: SourceCleanupSettings,
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        nextState.pendingSourceCleanupOffer = nil
        guard guardCanManageMods(in: &nextState) else {
            ModLibrary.discardImportPreview(preview)
            return nextState
        }

        guard preview.canInstall else {
            ModLibrary.discardImportPreview(preview)
            record(AppStrings.Status.noModFoldersInstalled, in: &nextState)
            return nextState
        }

        let accessURLs = preview.sourceURLs + preview.installableItems.map(\.sourceURL)
        let sourceTokens = accessURLs.map(SecurityScopedAccessToken.init(url:))
        defer {
            sourceTokens.forEach { $0.stop() }
            ModLibrary.discardImportPreview(preview)
        }

        do {
            let currentInstall = install(for: nextState)
            let addedModsShouldBeEnabled = shouldEnableAddedMods(in: nextState)
            let installResult = try performWithFolderAccess(state: &nextState) {
                try ModLibrary.installPreview(
                    preview,
                    into: currentInstall,
                    enabled: addedModsShouldBeEnabled,
                    archiveDirectory: currentInstall.archivedModsDirectoryURL
                )
            }
            return reconcileInstallResult(
                installResult,
                source: .selectedSources(preview.sourceURLs),
                shouldEnable: addedModsShouldBeEnabled,
                sourceCleanupSettings: sourceCleanupSettings,
                in: nextState
            )
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotAddMods(error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func setMod(_ mod: ModInfo, enabled: Bool, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        do {
            let destinationURL = try performWithFolderAccess(state: &nextState) {
                try ModLibrary.setEnabled(mod, enabled: enabled)
            }
            let changeMessage = enabled
                ? AppStrings.Status.enabledMod(mod.displayName)
                : AppStrings.Status.disabledMod(mod.displayName)
            record(changeMessage, in: &nextState)
            nextState = refreshedState(from: nextState)
            var savedState = saveCurrentStateToSelectedModSet(
                in: nextState,
                recordingSuccess: AppStrings.Status.updatedModSet(
                    after: changeMessage,
                    setName: nextState.modSetSelection.selectedSetName
                )
            )
            audit(
                enabled ? .modEnabled : .modDisabled,
                summary: savedState.activityMessage.isEmpty ? changeMessage : savedState.activityMessage,
                subjects: [auditSubjectForMod(mod, path: destinationURL.path)],
                in: &savedState
            )
            return savedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotUpdateMod(mod.displayName, errorDescription: error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func setMods(
        _ mods: [ModInfo],
        enabled: Bool,
        in state: ModManagerState
    ) -> ModManagerState {
        guard !mods.isEmpty else {
            return state
        }

        guard mods.count > 1 else {
            return setMod(mods[0], enabled: enabled, in: state)
        }

        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        var changedMods: [(mod: ModInfo, destinationURL: URL)] = []
        var failedMods: [(mod: ModInfo, error: any Error)] = []
        do {
            try performWithFolderAccess(state: &nextState) {
                for mod in mods {
                    do {
                        changedMods.append((mod, try ModLibrary.setEnabled(mod, enabled: enabled)))
                    } catch {
                        failedMods.append((mod, error))
                    }
                }
            }
        } catch is SecurityScopedFolderAccessError {
            // The folder-access coordinator already recorded the problem.
            return nextState
        } catch {
            record(
                AppStrings.Status.couldNotUpdateMod(
                    mods[0].displayName,
                    errorDescription: error.localizedDescription
                ),
                severity: .error,
                in: &nextState
            )
            return nextState
        }

        guard !changedMods.isEmpty else {
            if let firstFailure = failedMods.first {
                record(AppStrings.Status.couldNotUpdateMod(
                        firstFailure.mod.displayName,
                        errorDescription: firstFailure.error.localizedDescription
                    ), severity: .error, in: &nextState)
            }
            return nextState
        }

        var changeMessage = enabled
            ? AppStrings.Status.enabledMods(count: changedMods.count)
            : AppStrings.Status.disabledMods(count: changedMods.count)
        if let firstFailure = failedMods.first {
            changeMessage += " " + AppStrings.Status.couldNotUpdateMod(
                firstFailure.mod.displayName,
                errorDescription: firstFailure.error.localizedDescription
            )
        }
        record(changeMessage, in: &nextState)
        nextState = refreshedState(from: nextState)
        var savedState = saveCurrentStateToSelectedModSet(
            in: nextState,
            recordingSuccess: AppStrings.Status.updatedModSet(
                after: changeMessage,
                setName: nextState.modSetSelection.selectedSetName
            )
        )
        audit(
            enabled ? .modEnabled : .modDisabled,
            summary: savedState.activityMessage.isEmpty ? changeMessage : savedState.activityMessage,
            subjects: changedMods.map { auditSubjectForMod($0.mod, path: $0.destinationURL.path) },
            in: &savedState
        )
        return savedState
    }

    func deleteMod(_ mod: ModInfo, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        do {
            let currentInstall = install(for: nextState)
            let archivedURL = try performWithFolderAccess(state: &nextState) {
                try ModLibrary.archive(
                    mod,
                    in: currentInstall.archivedModsDirectoryURL
                )
            }
            let changeMessage = AppStrings.Status.deletedModArchived(mod.displayName)
            record(changeMessage, in: &nextState)
            nextState = refreshedState(from: nextState)
            var savedState = saveCurrentStateToSelectedModSet(
                in: nextState,
                recordingSuccess: AppStrings.Status.updatedModSet(
                    after: changeMessage,
                    setName: nextState.modSetSelection.selectedSetName
                )
            )
            audit(
                .modDeleted,
                summary: savedState.activityMessage.isEmpty ? changeMessage : savedState.activityMessage,
                subjects: [auditSubjectForMod(mod)],
                details: [
                    "archive_path": archivedURL.path,
                    "version": mod.manifest?.version?.trimmedNonEmpty ?? ""
                ],
                in: &savedState
            )
            return savedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotDeleteMod(mod.displayName, errorDescription: error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func resolveDuplicateGroup(id: String, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        guard let group = nextState.duplicateGroups.first(where: { $0.id == id }),
              group.mods.count > 1,
              let keptMod = preferredDuplicate(in: group.mods)
        else {
            return nextState
        }

        let modsToArchive = group.mods.filter { $0.id != keptMod.id }
        do {
            let currentInstall = install(for: nextState)
            let archivedURLs = try performWithFolderAccess(state: &nextState) {
                try modsToArchive.map { mod in
                    try ModLibrary.archive(
                        mod,
                        in: currentInstall.archivedModsDirectoryURL
                    )
                }
            }
            let changeMessage = AppStrings.Status.keptAndArchivedDuplicates(
                keptName: keptMod.displayName,
                count: modsToArchive.count
            )
            record(changeMessage, in: &nextState)
            nextState = refreshedState(from: nextState)
            var savedState = saveCurrentStateToSelectedModSet(
                in: nextState,
                recordingSuccess: AppStrings.Status.updatedModSet(
                    after: changeMessage,
                    setName: nextState.modSetSelection.selectedSetName
                )
            )
            audit(
                .duplicatesResolved,
                summary: savedState.activityMessage.isEmpty ? changeMessage : savedState.activityMessage,
                subjects: modsToArchive.map { auditSubjectForMod($0) },
                details: [
                    "kept_folder": keptMod.folderName,
                    "kept_version": keptMod.manifest?.version?.trimmedNonEmpty ?? "",
                    "archive_paths": archivedURLs.map(\.path).joined(separator: "\n")
                ],
                in: &savedState
            )
            return savedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(
                AppStrings.Status.couldNotResolveDuplicates(error.localizedDescription),
                severity: .error,
                in: &nextState
            )
            return nextState
        }
    }

    /// Picks the duplicate copy to keep: highest version first, then enabled
    /// over disabled, then the alphabetically first folder for stability.
    private func preferredDuplicate(in mods: [ModInfo]) -> ModInfo? {
        mods.max { lhs, rhs in
            let lhsVersion = lhs.manifest?.version?.trimmedNonEmpty
            let rhsVersion = rhs.manifest?.version?.trimmedNonEmpty
            switch (lhsVersion, rhsVersion) {
            case (nil, nil):
                break
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            case (.some(let lhsVersion), .some(let rhsVersion)):
                switch ModVersionComparator.compare(lhsVersion, to: rhsVersion) {
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                case .orderedSame:
                    break
                }
            }

            if lhs.isEnabled != rhs.isEnabled {
                return !lhs.isEnabled
            }

            return lhs.folderName.localizedCaseInsensitiveCompare(rhs.folderName) == .orderedDescending
        }
    }

    func restoreArchivedMods(
        _ archivedMods: [ArchivedModInfo],
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        guard !archivedMods.isEmpty else {
            record(AppStrings.Status.chooseArchivedModsToRestore, in: &nextState)
            return nextState
        }

        do {
            let currentInstall = install(for: nextState)
            let restoreResults = try performWithFolderAccess(state: &nextState) {
                try ModLibrary.restoreArchivedMods(
                    archivedMods,
                    into: currentInstall,
                    archiveDirectory: currentInstall.archivedModsDirectoryURL
                )
            }
            let changeMessage = restoreSummary(for: restoreResults)
            record(changeMessage, in: &nextState)
            nextState = refreshedState(from: nextState)
            var savedState = saveCurrentStateToSelectedModSet(
                in: nextState,
                recordingSuccess: AppStrings.Status.updatedModSet(
                    after: changeMessage,
                    setName: nextState.modSetSelection.selectedSetName
                )
            )
            audit(
                .modRestored,
                summary: savedState.activityMessage.isEmpty ? changeMessage : savedState.activityMessage,
                subjects: restoreResults.map(auditSubjectForRestoredMod),
                details: restoreDetails(for: restoreResults),
                in: &savedState
            )
            return savedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotRestoreArchivedMods(error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func pruneExpiredArchives(in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        do {
            let prunedCount = try pruneExpiredArchiveCount(in: nextState)
            record(AppStrings.Status.prunedExpiredArchives(count: prunedCount), in: &nextState)
            var refreshedState = refreshedState(from: nextState)
            auditArchivesPruned(
                count: prunedCount,
                summary: refreshedState.activityMessage,
                in: &refreshedState
            )
            return refreshedState
        } catch {
            record(AppStrings.Status.couldNotPruneArchivedMods(error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }
}
