import Foundation

/// The actor's public surface. Each method runs against the actor's canonical
/// `state`, commits the result, and returns the committed snapshot for the
/// caller to mirror.
extension ModManagerService {
    func refresh() -> ModManagerState {
        var nextState = stateStore.stateByRestoringSavedFolder(from: state)
        if stateStore.hasLastKnownModFolderTokens {
            nextState = reconcileStartupModsFolderChange(
                from: nextState,
                previousModFolderTokens: stateStore.lastKnownModFolderTokens,
                appliedModSetID: stateStore.lastAppliedModSetID
            )
        } else {
            nextState = refreshedState(from: nextState)
        }
        prepareLastSessionNotice(in: &nextState)
        return commit(nextState)
    }

    /// Refreshes state when the user returns to the app, catching changes —
    /// most importantly a new SMAPI log — written while Seed Box stayed open.
    func refreshAfterActivation() -> ModManagerState {
        var nextState = refreshedState(from: state)
        prepareLastSessionNotice(in: &nextState)
        return commit(nextState)
    }

    /// Announces a problematic game session once. The dedupe key is the log's
    /// creation date, which is stable while the game appends to the log, so
    /// repeated activations during one session never re-announce.
    private func prepareLastSessionNotice(in state: inout ModManagerState) {
        guard let report = state.lastSessionReport,
              let sessionDate = report.sessionStartedAt ?? report.generatedAt
        else {
            return
        }

        // The stored date round-trips through UserDefaults as a Double, so
        // exact equality can miss by a floating-point ulp.
        if let announcedDate = stateStore.announcedLogSessionDate,
           abs(announcedDate.timeIntervalSince1970 - sessionDate.timeIntervalSince1970) < 0.001 {
            return
        }

        let issues = state.lastSessionIssues
        guard !issues.isEmpty else {
            return
        }

        stateStore.announcedLogSessionDate = sessionDate
        state.pendingLastSessionNotice = LastSessionNotice(
            sessionDate: report.generatedAt ?? sessionDate,
            skippedModCount: issues.filter { $0.skippedReason != nil }.count,
            erroringModCount: issues.filter { $0.errorCount > 0 }.count
        )
    }

    func dismissLastSessionNotice() -> ModManagerState {
        guard state.pendingLastSessionNotice != nil else {
            return state
        }

        var nextState = state
        nextState.pendingLastSessionNotice = nil
        return commit(nextState)
    }

    /// Reconciles a folder change reported by the watcher. The watcher also
    /// fires for the app's own mutations, so instead of a timing window the
    /// rescan is compared against the current state: only a real difference
    /// counts as an external change worth surfacing.
    func reconcileObservedModsFolderChange() -> (state: ModManagerState, didObserveExternalChange: Bool) {
        let previousState = state
        var refreshed = refreshedState(from: previousState)
        let addedMods = addedMods(in: refreshed, comparedTo: previousState)

        guard addedMods.isEmpty else {
            let reconciled = reconcileAddedMods(
                addedMods,
                fallbackURLs: addedMods.map(\.url),
                source: .watchedFolder,
                shouldEnable: shouldEnableAddedMods(in: previousState),
                in: refreshed
            )
            return (commit(reconciled), true)
        }

        let didObserveExternalChange = refreshed.mods != previousState.mods
            || refreshed.invalidModFolders != previousState.invalidModFolders
        if didObserveExternalChange {
            record(AppStrings.Status.modsFolderChangedRefreshed, in: &refreshed)
        }
        return (commit(refreshed), didObserveExternalChange)
    }

    func chooseModsFolder(_ selectedURL: URL) -> ModManagerState {
        commit(chooseModsFolder(selectedURL, from: state))
    }

    func createModFolder() -> ModManagerState {
        commit(createModFolder(from: state))
    }

    func addMods(
        from selectedURLs: [URL],
        replacementPolicy: ModInstallReplacementPolicy = .newerOnly
    ) -> ModManagerState {
        commit(
            addMods(
                from: selectedURLs,
                sourceCleanupSettings: stateStore.sourceCleanupSettings,
                replacementPolicy: replacementPolicy,
                in: state
            )
        )
    }

    func addPreviewedMods(_ preview: ModImportPreview) -> ModManagerState {
        commit(
            addPreviewedMods(
                preview,
                sourceCleanupSettings: stateStore.sourceCleanupSettings,
                in: state
            )
        )
    }

    func setMod(_ mod: ModInfo, enabled: Bool) -> ModManagerState {
        commit(setMod(mod, enabled: enabled, in: state))
    }

    func setMods(_ mods: [ModInfo], enabled: Bool) -> ModManagerState {
        commit(setMods(mods, enabled: enabled, in: state))
    }

    func deleteMod(_ mod: ModInfo) -> ModManagerState {
        commit(deleteMod(mod, in: state))
    }

    func restoreArchivedMods(_ archivedMods: [ArchivedModInfo]) -> ModManagerState {
        commit(restoreArchivedMods(archivedMods, in: state))
    }

    func resolveDuplicateGroup(id: String) -> ModManagerState {
        commit(resolveDuplicateGroup(id: id, in: state))
    }

    func restorePreviousVersion(of mod: ModInfo) -> ModManagerState {
        guard let archivedMod = ModArchive.previousVersion(for: mod, in: state.archivedMods) else {
            return recordActivity(AppStrings.Status.noPreviousVersionAvailable(mod.displayName))
        }

        return restoreArchivedMods([archivedMod])
    }

    func pruneExpiredArchives() -> ModManagerState {
        commit(pruneExpiredArchives(in: state))
    }

    func createModSet(named name: String, from sourceSet: ModSet? = nil) -> ModManagerState {
        commit(createModSet(named: name, from: sourceSet, in: state))
    }

    func duplicateSelectedModSet(named name: String) -> ModManagerState {
        commit(duplicateSelectedModSet(named: name, in: state))
    }

    func renameSelectedModSet(to requestedName: String) -> ModManagerState {
        commit(renameSelectedModSet(to: requestedName, in: state))
    }

    func selectModSet(id: String) -> ModManagerState {
        commit(selectModSet(id: id, in: state))
    }

    func restoreSelectedModSet(id: String) -> ModManagerState {
        guard state.selectedModSetID != id else {
            return state
        }

        var nextState = state
        nextState.selectedModSetID = id
        return commit(nextState)
    }

    func deleteModSet(_ set: ModSet) -> ModManagerState {
        commit(deleteModSet(set, in: state))
    }

    func moveSourceFilesToTrash(
        for offer: SourceCleanupOffer,
        remembersChoice: Bool = false
    ) -> ModManagerState {
        if remembersChoice {
            stateStore.moveModFilesToTrashAfterAddingMods = true
            stateStore.suppressAddModsSuccessNotification = true
        }

        var nextState = moveSourceFilesToTrash(for: offer, in: state)
        mirrorSettings(in: &nextState)
        return commit(nextState)
    }

    func keepSourceFiles(for offer: SourceCleanupOffer, remembersChoice: Bool) -> ModManagerState {
        if remembersChoice {
            stateStore.moveModFilesToTrashAfterAddingMods = false
            stateStore.suppressAddModsSuccessNotification = true
        }

        var nextState = state
        mirrorSettings(in: &nextState)
        nextState.pendingSourceCleanupOffer = nil
        return commit(nextState)
    }

    func dismissSourceCleanupOffer() -> ModManagerState {
        guard state.pendingSourceCleanupOffer != nil else {
            return state
        }

        var nextState = state
        nextState.pendingSourceCleanupOffer = nil
        return commit(nextState)
    }

    func setMoveModFilesToTrashAfterAddingMods(_ isEnabled: Bool) -> ModManagerState {
        stateStore.moveModFilesToTrashAfterAddingMods = isEnabled
        return commitSettingsMirror()
    }

    func setSuppressAddModsSuccessNotification(_ isEnabled: Bool) -> ModManagerState {
        stateStore.suppressAddModsSuccessNotification = isEnabled
        return commitSettingsMirror()
    }

    func setAutomaticallyPrunesExpiredArchives(_ isEnabled: Bool) -> ModManagerState {
        stateStore.automaticallyPrunesExpiredArchives = isEnabled
        return commitSettingsMirror()
    }

    func setArchiveRetentionDays(_ days: Int) -> ModManagerState {
        stateStore.archiveRetentionDays = days
        return commitSettingsMirror()
    }

    func recordActivity(
        _ message: String,
        severity: StatusEvent.Severity = .info
    ) -> ModManagerState {
        var nextState = state
        record(message, severity: severity, in: &nextState)
        return commit(nextState)
    }

    /// Called when a main-actor collaborator (Finder reveal, import preview)
    /// hit a folder-access failure and already cleared the bookmark.
    func noteFolderAccessLost(message: String?) -> ModManagerState {
        var nextState = state
        nextState.hasSavedFolderAccess = false
        if let message {
            record(message, severity: .error, in: &nextState)
        }
        return commit(nextState)
    }

    /// Copies every preference-backed setting from the store into the state,
    /// so the state stays the single source the UI reads.
    func mirrorSettings(in state: inout ModManagerState) {
        state.archiveSettings = stateStore.archiveSettings
        state.sourceCleanupSettings = stateStore.sourceCleanupSettings
        state.checksForModUpdates = stateStore.checksForModUpdates
    }

    private func commitSettingsMirror() -> ModManagerState {
        var nextState = state
        mirrorSettings(in: &nextState)
        return commit(nextState)
    }
}
