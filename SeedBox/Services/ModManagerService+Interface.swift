import Foundation

struct ModManagerServiceResult<Value: Sendable>: Sendable {
    var state: ModManagerState
    var value: Value
}

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
                appliedModSetID: previousState.appliedModSetID,
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

    func setMod(id: ModInfo.ID, enabled: Bool) -> ModManagerState {
        guard let mod = state.mods.first(where: { $0.id == id }) else {
            return recordActivity(
                CocoaError(.fileNoSuchFile).localizedDescription,
                severity: .error
            )
        }
        return commit(setMod(mod, enabled: enabled, in: state))
    }

    func setModResult(
        id: ModInfo.ID,
        enabled: Bool,
        expectedEnabled: Bool? = nil
    ) -> ModManagerServiceResult<Bool> {
        guard let before = state.mods.first(where: { $0.id == id }),
              expectedEnabled == nil || before.isEnabled == expectedEnabled
        else {
            return ModManagerServiceResult(state: state, value: false)
        }

        let nextState = setMod(id: id, enabled: enabled)
        let didChange = before.isEnabled != enabled
            && nextState.mods.first(where: { $0.id == id })?.isEnabled == enabled
        return ModManagerServiceResult(state: nextState, value: didChange)
    }

    func setMods(ids: [ModInfo.ID], enabled: Bool) -> ModManagerState {
        let requestedIDs = Set(ids)
        let mods = state.mods.filter { requestedIDs.contains($0.id) }
        guard mods.count == requestedIDs.count else {
            return recordActivity(
                CocoaError(.fileNoSuchFile).localizedDescription,
                severity: .error
            )
        }
        return commit(setMods(mods, enabled: enabled, in: state))
    }

    func setModsResult(
        ids: [ModInfo.ID],
        enabled: Bool,
        expectedStates: [ModInfo.ID: Bool]? = nil
    ) -> ModManagerServiceResult<[ModEnabledStateMutation]> {
        let requestedIDs = Set(ids)
        let before = Dictionary(
            uniqueKeysWithValues: state.mods
                .filter { requestedIDs.contains($0.id) }
                .map { ($0.id, $0.isEnabled) }
        )
        guard before.count == requestedIDs.count else {
            return ModManagerServiceResult(
                state: recordActivity(
                    CocoaError(.fileNoSuchFile).localizedDescription,
                    severity: .error
                ),
                value: []
            )
        }
        if let expectedStates {
            guard expectedStates.count == requestedIDs.count,
                  expectedStates.allSatisfy({ before[$0.key] == $0.value })
            else {
                return ModManagerServiceResult(state: state, value: [])
            }
        }

        let nextState = setMods(ids: ids, enabled: enabled)
        let changes = ids.compactMap { id -> ModEnabledStateMutation? in
            guard let previousEnabled = before[id],
                  previousEnabled != enabled,
                  nextState.mods.first(where: { $0.id == id })?.isEnabled == enabled
            else {
                return nil
            }
            return ModEnabledStateMutation(
                modID: id,
                previousEnabled: previousEnabled,
                appliedEnabled: enabled
            )
        }
        return ModManagerServiceResult(state: nextState, value: changes)
    }

    func deleteMod(id: ModInfo.ID) -> ModManagerState {
        guard let mod = state.mods.first(where: { $0.id == id }) else {
            return recordActivity(
                CocoaError(.fileNoSuchFile).localizedDescription,
                severity: .error
            )
        }
        return commit(deleteMod(mod, in: state))
    }

    func deleteModResult(id: ModInfo.ID) -> ModManagerServiceResult<Bool> {
        let existed = state.mods.contains { $0.id == id }
        let nextState = deleteMod(id: id)
        return ModManagerServiceResult(
            state: nextState,
            value: existed && !nextState.mods.contains { $0.id == id }
        )
    }

    func restoreArchivedMods(ids: [ArchivedModInfo.ID]) -> ModManagerState {
        let requestedIDs = Set(ids)
        let archivedMods = state.archivedMods.filter { requestedIDs.contains($0.id) }
        guard archivedMods.count == requestedIDs.count else {
            return recordActivity(
                CocoaError(.fileNoSuchFile).localizedDescription,
                severity: .error
            )
        }
        return commit(restoreArchivedMods(archivedMods, in: state))
    }

    func restoreArchivedModsResult(
        ids: [ArchivedModInfo.ID]
    ) -> ModManagerServiceResult<[String]> {
        let requestedIDs = Set(ids)
        let candidates = state.archivedMods.filter { requestedIDs.contains($0.id) }
        let installedTokens = Set(state.mods.map { $0.enabledFolderName.normalizedFolderToken })
        let nextState = restoreArchivedMods(ids: ids)
        let restoredFolderNames = candidates.compactMap { archivedMod -> String? in
            let token = archivedMod.enabledFolderName.normalizedFolderToken
            guard !installedTokens.contains(token),
                  nextState.mods.contains(where: {
                      $0.enabledFolderName.normalizedFolderToken == token
                  })
            else {
                return nil
            }
            return archivedMod.enabledFolderName
        }
        return ModManagerServiceResult(state: nextState, value: restoredFolderNames)
    }

    func restoreMostRecentDeletedModResult(
        folderName: String
    ) -> ModManagerServiceResult<Bool> {
        let token = folderName.normalizedFolderToken
        guard let archive = state.archivedMods
            .filter({
                $0.reason == .deleted
                    && $0.enabledFolderName.normalizedFolderToken == token
            })
            .max(by: {
                ($0.archivedDate ?? .distantPast)
                    < ($1.archivedDate ?? .distantPast)
            })
        else {
            return ModManagerServiceResult(state: state, value: false)
        }

        let result = restoreArchivedModsResult(ids: [archive.id])
        return ModManagerServiceResult(
            state: result.state,
            value: result.value.contains {
                $0.normalizedFolderToken == token
            }
        )
    }

    func deleteInstalledModResult(
        folderName: String
    ) -> ModManagerServiceResult<Bool> {
        let token = folderName.normalizedFolderToken
        guard let mod = state.mods.first(where: {
            $0.enabledFolderName.normalizedFolderToken == token
        }) else {
            return ModManagerServiceResult(state: state, value: false)
        }
        return deleteModResult(id: mod.id)
    }

    func deleteArchivedMods(ids: [ArchivedModInfo.ID]) -> ModManagerState {
        let requestedIDs = Set(ids)
        let archivedMods = state.archivedMods.filter { requestedIDs.contains($0.id) }
        guard archivedMods.count == requestedIDs.count else {
            return recordActivity(
                CocoaError(.fileNoSuchFile).localizedDescription,
                severity: .error
            )
        }
        return commit(deleteArchivedMods(archivedMods, in: state))
    }

    func resolveDuplicateGroup(id: String) -> ModManagerState {
        commit(resolveDuplicateGroup(id: id, in: state))
    }

    func restorePreviousVersion(ofModWithID id: ModInfo.ID) -> ModManagerState {
        guard let mod = state.mods.first(where: { $0.id == id }) else {
            return recordActivity(
                CocoaError(.fileNoSuchFile).localizedDescription,
                severity: .error
            )
        }
        guard let archivedMod = ModArchive.previousVersion(for: mod, in: state.archivedMods) else {
            return recordActivity(AppStrings.Status.noPreviousVersionAvailable(mod.displayName))
        }

        return restoreArchivedMods(ids: [archivedMod.id])
    }

    func pruneExpiredArchives() -> ModManagerState {
        commit(pruneExpiredArchives(in: state))
    }

    func createModSet(
        named name: String,
        from sourceSet: ModSet? = nil,
        parentID: String? = nil
    ) -> ModManagerState {
        commit(createModSet(named: name, from: sourceSet, parentID: parentID, in: state))
    }

    func createModSetResult(
        named name: String,
        from sourceSet: ModSet? = nil,
        parentID: String? = nil
    ) -> ModManagerServiceResult<ModSet?> {
        let existingIDs = Set(state.modSets.map(\.id))
        let nextState = createModSet(named: name, from: sourceSet, parentID: parentID)
        let createdSet = nextState.modSets.first { !existingIDs.contains($0.id) }
        return ModManagerServiceResult(state: nextState, value: createdSet)
    }

    func duplicateSelectedModSet(named name: String, parentID: String? = nil) -> ModManagerState {
        commit(duplicateSelectedModSet(named: name, parentID: parentID, in: state))
    }

    func duplicateSelectedModSetResult(
        named name: String,
        parentID: String? = nil
    ) -> ModManagerServiceResult<ModSet?> {
        let existingIDs = Set(state.modSets.map(\.id))
        let nextState = duplicateSelectedModSet(named: name, parentID: parentID)
        let createdSet = nextState.modSets.first { !existingIDs.contains($0.id) }
        return ModManagerServiceResult(state: nextState, value: createdSet)
    }

    func renameSelectedModSet(to requestedName: String) -> ModManagerState {
        commit(renameSelectedModSet(to: requestedName, in: state))
    }

    func renameModSetResult(
        id: ModSet.ID,
        to requestedName: String,
        expectedName: String? = nil
    ) -> ModManagerServiceResult<Bool> {
        guard let before = state.modSets.first(where: { $0.id == id }),
              expectedName == nil || before.name == expectedName
        else {
            return ModManagerServiceResult(state: state, value: false)
        }

        let nextState = commit(renameModSet(id: id, to: requestedName, in: state))
        let didChange = before.name != requestedName
            && nextState.modSets.first(where: { $0.id == id })?.name == requestedName
        return ModManagerServiceResult(state: nextState, value: didChange)
    }

    func selectModSet(id: String) -> ModManagerState {
        commit(selectModSet(id: id, in: state))
    }

    func selectModSetResult(
        id: String,
        expectedSelectedSetID: String? = nil
    ) -> ModManagerServiceResult<Bool> {
        let beforeID = state.selectedModSetID
        guard expectedSelectedSetID == nil || beforeID == expectedSelectedSetID else {
            return ModManagerServiceResult(state: state, value: false)
        }

        let nextState = selectModSet(id: id)
        return ModManagerServiceResult(
            state: nextState,
            value: beforeID != id && nextState.selectedModSetID == id
        )
    }

    func restoreSelectedModSet(id: String) -> ModManagerState {
        guard state.selectedModSetID != id else {
            return state
        }

        var nextState = state
        nextState.selectedModSetID = id
        return commit(nextState)
    }

    func deleteModSet(id: ModSet.ID) -> ModManagerState {
        guard let set = state.modSets.first(where: { $0.id == id }) else {
            return recordActivity(
                CocoaError(.fileNoSuchFile).localizedDescription,
                severity: .error
            )
        }
        return commit(deleteModSet(set, in: state))
    }

    func deleteModSetResult(id: ModSet.ID) -> ModManagerServiceResult<Bool> {
        let existed = state.modSets.contains { $0.id == id }
        let nextState = deleteModSet(id: id)
        return ModManagerServiceResult(
            state: nextState,
            value: existed && !nextState.modSets.contains { $0.id == id }
        )
    }

    func restoreModSet(_ set: ModSet) -> ModManagerState {
        commit(restoreModSet(set, in: state))
    }

    func restoreModSetResult(_ set: ModSet) -> ModManagerServiceResult<Bool> {
        let existed = state.modSets.contains { $0.id == set.id }
        let nextState = restoreModSet(set)
        return ModManagerServiceResult(
            state: nextState,
            value: !existed && nextState.modSets.contains { $0.id == set.id }
        )
    }

    func importModSet(fromFileAt url: URL) -> ModManagerState {
        commit(importModSet(fromFileAt: url, in: state))
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
