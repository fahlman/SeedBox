import Foundation

actor ModManagerService {
    let folderAccessCoordinator: ModManagerFolderAccessCoordinator
    let auditRecorder: ModManagerAuditRecorder
    let modSetDirectory: URL

    init(
        folderAccess: SecurityScopedFolderAccess,
        modSetDirectory: URL = StardewInstall.defaultModSetDirectory(),
        auditLogURL: URL? = nil
    ) {
        folderAccessCoordinator = ModManagerFolderAccessCoordinator(folderAccess: folderAccess)
        self.modSetDirectory = modSetDirectory
        let auditLogURL = auditLogURL ?? StardewInstall.auditLogURL(forModSetDirectory: modSetDirectory)
        auditRecorder = ModManagerAuditRecorder(logURL: auditLogURL)
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
        return nextState
    }

    func reconcileObservedModsFolderChange(from state: ModManagerState) -> ModManagerState {
        var refreshedState = refreshedState(from: state)
        let addedMods = addedMods(in: refreshedState, comparedTo: state)

        guard !addedMods.isEmpty else {
            record(AppStrings.Status.modsFolderChangedRefreshed, in: &refreshedState)
            return refreshedState
        }

        return reconcileAddedMods(
            addedMods,
            fallbackURLs: addedMods.map(\.url),
            source: .watchedFolder,
            shouldEnable: shouldEnableAddedMods(in: state),
            in: refreshedState
        )
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
            record(AppStrings.Status.couldNotSaveFolderAccess(error.localizedDescription), in: &nextState)
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
            record(AppStrings.Status.couldNotCreateModFolder(error.localizedDescription), in: &nextState)
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
            record(AppStrings.Status.couldNotAddMods(error.localizedDescription), in: &nextState)
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
            record(AppStrings.Status.couldNotAddMods(error.localizedDescription), in: &nextState)
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
            record(AppStrings.Status.couldNotUpdateMod(mod.displayName, errorDescription: error.localizedDescription), in: &nextState)
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

        var nextState = state
        for mod in mods {
            nextState = setMod(mod, enabled: enabled, in: nextState)
        }
        return nextState
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
            record(AppStrings.Status.couldNotDeleteMod(mod.displayName, errorDescription: error.localizedDescription), in: &nextState)
            return nextState
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
            record(AppStrings.Status.couldNotRestoreArchivedMods(error.localizedDescription), in: &nextState)
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
            record(AppStrings.Status.couldNotPruneArchivedMods(error.localizedDescription), in: &nextState)
            return nextState
        }
    }

    func createModSet(
        named name: String,
        from sourceSet: ModSet? = nil,
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        let source = sourceSet ?? ModSetStore.snapshotSet(
            id: "current",
            name: AppStrings.ModSetNames.current,
            from: nextState.mods
        )

        do {
            let newSet = try ModSetStore.createSet(
                named: name,
                from: source,
                existingSets: nextState.modSets
            )

            try ModSetStore.saveSet(
                newSet,
                install: install(for: nextState)
            )

            let createdSetMatchesCurrentMods = sourceSet == nil
                || nextState.appliedModSetID == sourceSet?.id
            setSelectedModSetID(newSet.id, in: &nextState)
            nextState.appliedModSetID = createdSetMatchesCurrentMods ? newSet.id : nil
            record(AppStrings.Status.createdModSet(newSet.name), in: &nextState)
            var refreshedState = refreshedState(from: nextState)
            audit(
                .modSetCreated,
                summary: refreshedState.activityMessage,
                subjects: [auditSubjectForModSet(newSet)],
                details: [
                    "source_mod_set_id": sourceSet?.id ?? "current",
                    "source_mod_set_name": sourceSet?.name ?? AppStrings.ModSetNames.current
                ],
                in: &refreshedState
            )
            return refreshedState
        } catch {
            record(AppStrings.Status.couldNotCreateModSet(error.localizedDescription), in: &nextState)
            return nextState
        }
    }

    func duplicateSelectedModSet(named name: String, in state: ModManagerState) -> ModManagerState {
        guard let selectedSet = state.modSetSelection.selectedSet else {
            return state
        }

        return createModSet(named: name, from: selectedSet, in: state)
    }

    func renameSelectedModSet(to requestedName: String, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        guard var selectedSet = nextState.modSetSelection.selectedSet else {
            return nextState
        }
        guard selectedSet.isUserEditable else {
            record(AppStrings.Status.includedModSetNamesCannotBeChanged, in: &nextState)
            return nextState
        }

        let trimmedName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            record(AppStrings.Status.setNameCannotBeEmpty, in: &nextState)
            return nextState
        }

        let hasConflict = nextState.modSets.contains { set in
            set.id != selectedSet.id
                && set.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == trimmedName.lowercased()
        }
        if hasConflict {
            record(AppStrings.Errors.duplicateModSetName(trimmedName), in: &nextState)
            return nextState
        }

        let oldName = selectedSet.name
        selectedSet.name = trimmedName

        do {
            try ModSetStore.saveSet(
                selectedSet,
                install: install(for: nextState)
            )
            record(AppStrings.Status.renamedSet(to: trimmedName), in: &nextState)
            var refreshedState = refreshedState(from: nextState)
            audit(
                .modSetRenamed,
                summary: refreshedState.activityMessage,
                subjects: [auditSubjectForModSet(selectedSet)],
                details: [
                    "old_name": oldName,
                    "new_name": trimmedName
                ],
                in: &refreshedState
            )
            return refreshedState
        } catch {
            record(AppStrings.Status.couldNotRenameModSet(error.localizedDescription), in: &nextState)
            return nextState
        }
    }

    func selectModSet(id: String, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        let isReapplyingSelectedSet = nextState.selectedModSetID == id
        guard !isReapplyingSelectedSet || nextState.appliedModSetID != id else {
            return nextState
        }

        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        guard let setToApply = nextState.modSets.first(where: { $0.id == id }) else {
            record(AppStrings.Status.couldNotApplySetSelectionMissing, in: &nextState)
            return nextState
        }

        do {
            if !isReapplyingSelectedSet,
               let previousSet = nextState.modSetSelection.selectedSet {
                try saveCurrentStateIfEditable(to: previousSet, in: nextState)
            }

            let changedCount = try applyModSet(setToApply, in: nextState, state: &nextState)
            setSelectedModSetID(id, in: &nextState)
            nextState.appliedModSetID = id
            record(AppStrings.Status.appliedSet(setToApply.name, changedCount: changedCount), in: &nextState)
            var refreshedState = refreshedState(from: nextState)
            audit(
                .modSetApplied,
                summary: refreshedState.activityMessage,
                subjects: [auditSubjectForModSet(setToApply)],
                details: [
                    "changed_count": "\(changedCount)"
                ],
                in: &refreshedState
            )
            return refreshedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotApplySet(error.localizedDescription), in: &nextState)
            return nextState
        }
    }

    func deleteModSet(_ set: ModSet, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        do {
            try ModSetStore.deleteSet(
                set,
                install: install(for: nextState)
            )
        } catch {
            record(AppStrings.Status.couldNotDeleteModSet(error.localizedDescription), in: &nextState)
            return nextState
        }

        guard nextState.selectedModSetID == set.id else {
            if nextState.appliedModSetID == set.id {
                nextState.appliedModSetID = nil
            }

            record(AppStrings.Status.deletedModSet(set.name), in: &nextState)
            var refreshedState = refreshedState(from: nextState)
            auditDeletedModSet(set, wasSelected: false, in: &refreshedState)
            return refreshedState
        }

        guard let defaultSet = nextState.modSets.first(where: { $0.id == ModSetStore.defaultSetID }) else {
            setSelectedModSetID(ModSetStore.defaultSetID, in: &nextState)
            nextState.appliedModSetID = nil
            record(AppStrings.Status.deletedModSet(set.name), in: &nextState)
            var refreshedState = refreshedState(from: nextState)
            auditDeletedModSet(set, wasSelected: true, in: &refreshedState)
            return refreshedState
        }

        do {
            let changedCount = try applyModSet(defaultSet, in: nextState, state: &nextState)
            setSelectedModSetID(ModSetStore.defaultSetID, in: &nextState)
            nextState.appliedModSetID = ModSetStore.defaultSetID
            record(
                AppStrings.Status.deletedModSetAppliedDefault(set.name, changedCount: changedCount),
                in: &nextState
            )
            var refreshedState = refreshedState(from: nextState)
            auditDeletedModSet(
                set,
                wasSelected: true,
                details: [
                    "fallback_mod_set_id": defaultSet.id,
                    "fallback_mod_set_name": defaultSet.name,
                    "fallback_changed_count": "\(changedCount)"
                ],
                in: &refreshedState
            )
            return refreshedState
        } catch is SecurityScopedFolderAccessError {
            setSelectedModSetID(ModSetStore.defaultSetID, in: &nextState)
            nextState.appliedModSetID = nil
            record(AppStrings.Status.deletedModSetChooseFolderAgainToApplyDefault(set.name), in: &nextState)
            return refreshedState(from: nextState)
        } catch {
            setSelectedModSetID(ModSetStore.defaultSetID, in: &nextState)
            nextState.appliedModSetID = nil
            record(AppStrings.Status.deletedModSetCouldNotApplyDefault(set.name, errorDescription: error.localizedDescription), in: &nextState)
            return refreshedState(from: nextState)
        }
    }

}
