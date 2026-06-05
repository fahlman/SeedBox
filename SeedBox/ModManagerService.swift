import Foundation

actor ModManagerService {
    private let folderAccess: SecurityScopedFolderAccess
    private let auditLogURL: URL
    private let modSetDirectory: URL
    private var lastFolderAccessError: String?

    init(
        folderAccess: SecurityScopedFolderAccess,
        modSetDirectory: URL = StardewInstall.defaultModSetDirectory(),
        auditLogURL: URL? = nil
    ) {
        self.folderAccess = folderAccess
        self.modSetDirectory = modSetDirectory
        self.auditLogURL = auditLogURL ?? StardewInstall.auditLogURL(forModSetDirectory: modSetDirectory)
    }

    func refreshedState(from state: ModManagerState) -> ModManagerState {
        var nextState = state
        nextState.hasSavedFolderAccess = folderAccess.hasBookmark
        let install = install(for: nextState)

        if nextState.hasSavedFolderAccess {
            nextState.status = withFolderAccess(state: &nextState) {
                install.status()
            } ?? install.status()
        } else {
            nextState.status = install.status()
        }

        reloadMods(in: &nextState)
        reloadModSets(in: &nextState)
        reloadAuditTrail(in: &nextState)
        pruneExpiredArchivedMods(in: &nextState)
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
            shouldEnable: state.appliedModSetID != ModSetStore.noneSetID,
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
            shouldEnable: appliedModSetID != ModSetStore.noneSetID,
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
            try folderAccess.saveBookmark(for: resolvedURL)
            nextState.hasSavedFolderAccess = folderAccess.hasBookmark
            lastFolderAccessError = nil
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
            let addedModsShouldBeEnabled = nextState.appliedModSetID != ModSetStore.noneSetID
            let installResult = try performWithFolderAccess(state: &nextState) {
                try ModLibrary.installMods(
                    from: selectedURLs,
                    into: currentInstall,
                    enabled: addedModsShouldBeEnabled,
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

    func moveSourceFilesToTrash(
        for offer: SourceCleanupOffer,
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        nextState.pendingSourceCleanupOffer = nil

        let cleanupResult = trashSourceFiles(offer.sourceURLs)
        let summary = sourceTrashSummary(for: cleanupResult)
        auditSourceTrashResult(
            cleanupResult,
            sourceURLs: offer.sourceURLs,
            summary: summary,
            in: &nextState
        )
        return nextState
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

    private func install(for state: ModManagerState) -> StardewInstall {
        StardewInstall(
            modsDirectory: URL(fileURLWithPath: state.modsDirectoryPath, isDirectory: true),
            modSetDirectory: modSetDirectory
        )
    }

    private func reloadMods(in state: inout ModManagerState) {
        guard state.readiness.canManageMods else {
            state.mods = []
            state.hasLoadedMods = false
            return
        }

        do {
            let currentInstall = install(for: state)
            state.mods = try performWithFolderAccess(state: &state) {
                try ModLibrary.scan(install: currentInstall)
            }
            state.hasLoadedMods = true
        } catch is SecurityScopedFolderAccessError {
            state.mods = []
            state.hasLoadedMods = false
        } catch {
            state.mods = []
            state.hasLoadedMods = false
            record(AppStrings.Status.couldNotReadMods(error.localizedDescription), in: &state)
        }
    }

    private func reloadModSets(in state: inout ModManagerState) {
        guard state.readiness.canManageMods else {
            state.modSets = []
            setSelectedModSetID(ModSetStore.defaultSetID, in: &state)
            state.appliedModSetID = nil
            return
        }

        do {
            let loadedSets = try ModSetStore.loadSets(
                install: install(for: state),
                currentMods: state.mods
            )

            state.modSets = loadedSets
            if !loadedSets.contains(where: { $0.id == state.selectedModSetID }) {
                setSelectedModSetID(ModSetStore.defaultSetID, in: &state)
            }
            if let appliedModSetID = state.appliedModSetID,
               !loadedSets.contains(where: { $0.id == appliedModSetID }) {
                state.appliedModSetID = nil
            }
            if let appliedSet = state.appliedModSetID.flatMap({ appliedID in
                loadedSets.first { $0.id == appliedID }
            }), !modSetMatchesCurrentMods(appliedSet, in: state) {
                state.appliedModSetID = nil
            }
            if state.appliedModSetID == nil,
               let selectedSet = state.modSetSelection.selectedSet,
               modSetMatchesCurrentMods(selectedSet, in: state) {
                state.appliedModSetID = selectedSet.id
            }
        } catch {
            state.modSets = []
            setSelectedModSetID(ModSetStore.defaultSetID, in: &state)
            state.appliedModSetID = nil
            record(AppStrings.Status.couldNotReadModSets(error.localizedDescription), in: &state)
        }
    }

    private func reloadAuditTrail(in state: inout ModManagerState) {
        state.auditTrail.logPath = auditLogURL.path

        do {
            state.auditTrail.recentEntries = try AuditLogStore.loadEntries(
                from: auditLogURL,
                limit: AuditLogStore.recentEntryLimit
            )
            state.auditTrail.lastErrorMessage = nil
        } catch {
            state.auditTrail.lastErrorMessage = error.localizedDescription
        }
    }

    private func pruneExpiredArchivedMods(in state: inout ModManagerState) {
        do {
            try ModArchive.pruneExpiredArchives(
                in: install(for: state).archivedModsDirectoryURL
            )
        } catch {
            record(AppStrings.Status.couldNotPruneArchivedMods(error.localizedDescription), in: &state)
        }
    }

    private enum AddedModSource {
        case selectedSources([URL])
        case startupScan
        case watchedFolder

        var details: [String: String] {
            switch self {
            case .selectedSources(let urls):
                return [
                    "source": "selected_sources",
                    "source_paths": urls.map(\.path).joined(separator: "\n")
                ]
            case .startupScan:
                return [
                    "source": "startup_scan"
                ]
            case .watchedFolder:
                return [
                    "source": "watched_folder"
                ]
            }
        }
    }

    private func reconcileAddedMods(
        installedURLs: [URL],
        source: AddedModSource,
        shouldEnable: Bool,
        in state: ModManagerState
    ) -> ModManagerState {
        let installedTokens = Set(installedURLs.map { $0.lastPathComponent.normalizedFolderToken })
        let refreshedState = refreshedState(from: state)
        let addedMods = refreshedState.mods.filter { mod in
            installedTokens.contains(mod.enabledFolderName.normalizedFolderToken)
        }

        return reconcileAddedMods(
            addedMods,
            fallbackURLs: installedURLs,
            source: source,
            shouldEnable: shouldEnable,
            in: refreshedState
        )
    }

    private func reconcileInstallResult(
        _ installResult: ModInstallResult,
        source: AddedModSource,
        shouldEnable: Bool,
        sourceCleanupSettings: SourceCleanupSettings,
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        let installedTokens = Set(
            installResult.installed
                .map(\.destinationURL.lastPathComponent)
                .map(\.normalizedFolderToken)
        )
        let changeMessage = installSummary(for: installResult)

        do {
            if !installResult.installed.isEmpty {
                let currentInstall = install(for: nextState)
                try performWithFolderAccess(state: &nextState) {
                    let currentMods = try ModLibrary.scan(install: currentInstall)
                    for mod in currentMods where installedTokens.contains(mod.enabledFolderName.normalizedFolderToken) {
                        _ = try ModLibrary.setEnabled(mod, enabled: shouldEnable)
                    }
                }
            }

            nextState = refreshedState(from: nextState)
            record(changeMessage, in: &nextState)

            let savedState: ModManagerState
            if !installResult.installed.isEmpty {
                savedState = saveCurrentStateToSelectedModSet(
                    in: nextState,
                    recordingSuccess: AppStrings.Status.updatedModSet(
                        after: changeMessage,
                        setName: nextState.modSetSelection.selectedSetName
                    )
                )
            } else {
                savedState = nextState
            }

            var auditedState = savedState
            var details = installDetails(
                for: installResult,
                source: source,
                shouldEnable: shouldEnable
            )
            details["archive_retention_days"] = "\(Int(ModArchive.retentionInterval / 86_400))"
            audit(
                auditAction(for: installResult),
                summary: auditedState.activityMessage.isEmpty ? changeMessage : auditedState.activityMessage,
                subjects: auditSubjects(for: installResult),
                details: details,
                in: &auditedState
            )
            prepareSourceCleanupPresentation(
                for: installResult,
                source: source,
                importSummary: changeMessage,
                settings: sourceCleanupSettings,
                in: &auditedState
            )
            return auditedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotReconcileInstalledMods(error.localizedDescription), in: &nextState)
            return nextState
        }
    }

    private func reconcileAddedMods(
        _ addedMods: [ModInfo],
        fallbackURLs: [URL],
        source: AddedModSource,
        shouldEnable: Bool,
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        let addedTokens = Set(
            (addedMods.map(\.enabledFolderName) + fallbackURLs.map(\.lastPathComponent))
                .map(\.normalizedFolderToken)
        )
        let addedCount = max(addedMods.count, fallbackURLs.count)
        let changeMessage = AppStrings.Status.addedModFolders(count: addedCount)

        do {
            try performWithFolderAccess(state: &nextState) {
                for mod in addedMods {
                    _ = try ModLibrary.setEnabled(mod, enabled: shouldEnable)
                }
            }

            nextState = refreshedState(from: nextState)
            let finalAddedURLs = finalAddedModURLs(
                matching: addedTokens,
                fallbackURLs: fallbackURLs,
                in: nextState
            )

            record(changeMessage, in: &nextState)
            var savedState = saveCurrentStateToSelectedModSet(
                in: nextState,
                recordingSuccess: AppStrings.Status.updatedModSet(
                    after: changeMessage,
                    setName: nextState.modSetSelection.selectedSetName
                )
            )
            var details = source.details
            details["installed_state"] = shouldEnable ? "enabled" : "disabled"
            details["destination_paths"] = finalAddedURLs.map(\.path).joined(separator: "\n")
            audit(
                .modsAdded,
                summary: savedState.activityMessage.isEmpty ? changeMessage : savedState.activityMessage,
                subjects: finalAddedURLs.map(auditSubjectForInstalledMod),
                details: details,
                in: &savedState
            )
            return savedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotReconcileAddedMods(error.localizedDescription), in: &nextState)
            return nextState
        }
    }

    private func installSummary(for installResult: ModInstallResult) -> String {
        if installResult.installed.isEmpty,
           installResult.updated.isEmpty,
           installResult.skipped.count == 1,
           let skipped = installResult.skipped.first {
            switch skipped.reason {
            case .alreadyInstalled:
                return AppStrings.Status.alreadyInstalledMod(skipped.displayName)
            case .duplicateInSelection:
                return AppStrings.Status.duplicatedSelectedMod(skipped.displayName)
            }
        }

        if installResult.installed.isEmpty,
           installResult.updated.count == 1,
           installResult.skipped.isEmpty,
           let updated = installResult.updated.first {
            return AppStrings.Status.updatedMod(
                updated.displayName,
                previousVersion: updated.previousVersion,
                installedVersion: updated.installedVersion
            )
        }

        var sentences: [String] = []
        if !installResult.installed.isEmpty {
            sentences.append(AppStrings.Status.addedModFoldersSentence(count: installResult.installed.count))
        }
        if !installResult.updated.isEmpty {
            sentences.append(AppStrings.Status.updatedModFolders(count: installResult.updated.count))
        }
        if !installResult.skipped.isEmpty {
            let alreadyInstalledCount = installResult.skipped.filter { $0.reason == .alreadyInstalled }.count
            let duplicateSelectionCount = installResult.skipped.count - alreadyInstalledCount

            if alreadyInstalledCount > 0 {
                sentences.append(AppStrings.Status.skippedAlreadyInstalledMods(count: alreadyInstalledCount))
            }
            if duplicateSelectionCount > 0 {
                sentences.append(AppStrings.Status.skippedDuplicatedSelectedMods(count: duplicateSelectionCount))
            }
        }

        guard !sentences.isEmpty else {
            return AppStrings.Status.noModFoldersInstalled
        }

        return sentences.joined(separator: " ")
    }

    private func auditAction(for installResult: ModInstallResult) -> AuditLogAction {
        if !installResult.installed.isEmpty {
            return .modsAdded
        }

        if !installResult.updated.isEmpty {
            return .modsUpdated
        }

        return .modsInstallSkipped
    }

    private func auditSubjects(for installResult: ModInstallResult) -> [AuditLogSubject] {
        let installedSubjects = installResult.installed.map { install in
            AuditLogSubject(
                kind: .mod,
                id: nil,
                name: install.displayName,
                path: install.destinationURL.path
            )
        }
        let updatedSubjects = installResult.updated.map { update in
            AuditLogSubject(
                kind: .mod,
                id: nil,
                name: update.displayName,
                path: update.destinationURL.path
            )
        }
        let skippedSubjects = installResult.skipped.map { skipped in
            AuditLogSubject(
                kind: .mod,
                id: nil,
                name: skipped.displayName,
                path: skipped.existingURL?.path ?? skipped.sourceURL.path
            )
        }

        return installedSubjects + updatedSubjects + skippedSubjects
    }

    private func installDetails(
        for installResult: ModInstallResult,
        source: AddedModSource,
        shouldEnable: Bool
    ) -> [String: String] {
        var details = source.details
        details["installed_state"] = shouldEnable ? "enabled" : "disabled"
        details["added_count"] = "\(installResult.installed.count)"
        details["updated_count"] = "\(installResult.updated.count)"
        details["skipped_count"] = "\(installResult.skipped.count)"
        details["destination_paths"] = installResult.installedURLs.map(\.path).joined(separator: "\n")
        details["archive_paths"] = installResult.updated.map(\.archivedURL.path).joined(separator: "\n")
        details["skipped_mods"] = installResult.skipped.map { skipped in
            "\(skipped.displayName): \(skipped.reason.auditText)"
        }
        .joined(separator: "\n")
        details["version_changes"] = installResult.updated.map { update in
            "\(update.displayName): \(update.previousVersion ?? "unknown") -> \(update.installedVersion ?? "unknown")"
        }
        .joined(separator: "\n")
        return details
    }

    private struct SourceTrashFailure {
        var url: URL
        var message: String
    }

    private struct SourceTrashResult {
        var movedURLs: [URL] = []
        var failures: [SourceTrashFailure] = []
    }

    private func prepareSourceCleanupPresentation(
        for installResult: ModInstallResult,
        source: AddedModSource,
        importSummary: String,
        settings: SourceCleanupSettings,
        in state: inout ModManagerState
    ) {
        guard installResult.didChangeInstalledMods,
              case .selectedSources(let selectedURLs) = source
        else {
            state.pendingSourceCleanupOffer = nil
            return
        }

        let cleanableURLs = cleanableSourceURLs(
            selectedURLs,
            excludingDescendantsOf: install(for: state).modDirectoryURL
        )
        guard !cleanableURLs.isEmpty else {
            state.pendingSourceCleanupOffer = nil
            return
        }

        if settings.moveModFilesToTrashAfterAddingMods {
            let cleanupResult = trashSourceFiles(cleanableURLs)
            let cleanupSummary = sourceTrashSummary(for: cleanupResult)
            auditSourceTrashResult(
                cleanupResult,
                sourceURLs: cleanableURLs,
                summary: cleanupSummary,
                in: &state
            )

            state.pendingSourceCleanupOffer = settings.suppressAddModsSuccessNotification
                ? nil
                : SourceCleanupOffer(
                    sourceURLs: cleanableURLs,
                    importSummary: importSummary,
                    cleanupSummary: cleanupSummary,
                    isNotificationOnly: true
                )
            return
        }

        guard !settings.suppressAddModsSuccessNotification else {
            state.pendingSourceCleanupOffer = nil
            return
        }

        state.pendingSourceCleanupOffer = SourceCleanupOffer(
            sourceURLs: cleanableURLs,
            importSummary: importSummary
        )
    }

    private func cleanableSourceURLs(
        _ sourceURLs: [URL],
        excludingDescendantsOf excludedDirectoryURL: URL
    ) -> [URL] {
        let excludedPath = standardizedPath(for: excludedDirectoryURL)
        var seenPaths: Set<String> = []
        var cleanableURLs: [URL] = []

        for sourceURL in sourceURLs {
            let sourcePath = standardizedPath(for: sourceURL)
            guard !sourcePath.isEmpty,
                  sourcePath != excludedPath,
                  !sourcePath.hasPrefix(excludedPath + "/"),
                  !seenPaths.contains(sourcePath)
            else {
                continue
            }

            seenPaths.insert(sourcePath)
            cleanableURLs.append(sourceURL)
        }

        return cleanableURLs
    }

    private func trashSourceFiles(_ sourceURLs: [URL]) -> SourceTrashResult {
        var result = SourceTrashResult()

        for sourceURL in sourceURLs {
            let token = SecurityScopedAccessToken(url: sourceURL)
            defer {
                token.stop()
            }

            do {
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    result.failures.append(
                        SourceTrashFailure(
                            url: sourceURL,
                            message: AppStrings.SourceCleanup.fileNoLongerExists
                        )
                    )
                    continue
                }

                var resultingURL: NSURL?
                try FileManager.default.trashItem(
                    at: sourceURL,
                    resultingItemURL: &resultingURL
                )
                result.movedURLs.append((resultingURL as URL?) ?? sourceURL)
            } catch {
                result.failures.append(
                    SourceTrashFailure(
                        url: sourceURL,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return result
    }

    private func sourceTrashSummary(for result: SourceTrashResult) -> String {
        let movedCount = result.movedURLs.count
        let failedCount = result.failures.count

        guard movedCount > 0 else {
            return AppStrings.SourceCleanup.couldNotMoveOriginalFilesToTrash(count: failedCount)
        }

        return AppStrings.SourceCleanup.movedOriginalFilesToTrash(
            movedCount: movedCount,
            failedCount: failedCount
        )
    }

    private func auditSourceTrashResult(
        _ result: SourceTrashResult,
        sourceURLs: [URL],
        summary: String,
        in state: inout ModManagerState
    ) {
        record(summary, in: &state)
        guard !result.movedURLs.isEmpty else {
            return
        }

        audit(
            .sourceFilesMovedToTrash,
            summary: summary,
            subjects: result.movedURLs.map(auditSubjectForSourceFile),
            details: [
                "source_paths": sourceURLs.map(\.path).joined(separator: "\n"),
                "trashed_paths": result.movedURLs.map(\.path).joined(separator: "\n"),
                "failed_paths": result.failures.map(\.url.path).joined(separator: "\n"),
                "failure_messages": result.failures.map(\.message).joined(separator: "\n")
            ],
            in: &state
        )
    }

    private func standardizedPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func addedMods(
        in currentState: ModManagerState,
        comparedTo previousState: ModManagerState
    ) -> [ModInfo] {
        let previousTokens = Set(previousState.mods.map { $0.enabledFolderName.normalizedFolderToken })
        return addedMods(in: currentState, comparedTo: previousTokens)
    }

    private func addedMods(
        in currentState: ModManagerState,
        comparedTo previousTokens: Set<String>
    ) -> [ModInfo] {
        return currentState.mods.filter { mod in
            !previousTokens.contains(mod.enabledFolderName.normalizedFolderToken)
        }
    }

    private func finalAddedModURLs(
        matching addedTokens: Set<String>,
        fallbackURLs: [URL],
        in state: ModManagerState
    ) -> [URL] {
        let finalURLs = state.mods
            .filter { addedTokens.contains($0.enabledFolderName.normalizedFolderToken) }
            .map(\.url)

        return finalURLs.isEmpty ? fallbackURLs : finalURLs
    }

    private func saveCurrentStateToSelectedModSet(
        in state: ModManagerState,
        recordingSuccess successMessage: String? = nil
    ) -> ModManagerState {
        var nextState = state
        guard let selectedSet = nextState.modSetSelection.selectedSet else {
            nextState.appliedModSetID = nil
            return nextState
        }
        guard selectedSet.isUserEditable else {
            if modSetMatchesCurrentMods(selectedSet, in: nextState) {
                nextState.appliedModSetID = selectedSet.id
            } else if nextState.appliedModSetID == selectedSet.id {
                nextState.appliedModSetID = nil
            }
            return nextState
        }

        do {
            try saveCurrentState(to: selectedSet, in: nextState)
            nextState.appliedModSetID = selectedSet.id
            record(successMessage ?? AppStrings.Status.updatedModSet(selectedSet.name), in: &nextState)
            return refreshedState(from: nextState)
        } catch {
            record(AppStrings.Status.couldNotSaveModSet(error.localizedDescription), in: &nextState)
            return nextState
        }
    }

    private func applyModSet(
        _ set: ModSet,
        in currentState: ModManagerState,
        state: inout ModManagerState
    ) throws -> Int {
        try performWithFolderAccess(state: &state) {
            try ModSetStore.applySet(
                set,
                install: install(for: currentState)
            )
        }
    }

    private func saveCurrentState(to set: ModSet, in state: ModManagerState) throws {
        guard set.isUserEditable else {
            throw ModSetStoreError.cannotEditIncludedSet
        }

        var updatedSet = set
        updatedSet.disabledFolderNames = ModSetStore.snapshotSet(
            id: set.id,
            name: set.name,
            from: state.mods
        )
        .disabledFolderNames

        try ModSetStore.saveSet(
            updatedSet,
            install: install(for: state)
        )
    }

    private func saveCurrentStateIfEditable(to set: ModSet, in state: ModManagerState) throws {
        guard set.isUserEditable else {
            return
        }

        try saveCurrentState(to: set, in: state)
    }

    private func auditDeletedModSet(
        _ set: ModSet,
        wasSelected: Bool,
        details: [String: String] = [:],
        in state: inout ModManagerState
    ) {
        var mergedDetails = details
        mergedDetails["was_selected"] = wasSelected ? "true" : "false"

        audit(
            .modSetDeleted,
            summary: state.activityMessage,
            subjects: [auditSubjectForModSet(set)],
            details: mergedDetails,
            in: &state
        )
    }

    private func audit(
        _ action: AuditLogAction,
        summary: String,
        subjects: [AuditLogSubject] = [],
        details: [String: String] = [:],
        in state: inout ModManagerState
    ) {
        let entry = AuditLogEntry(
            action: action,
            summary: summary,
            modsDirectoryPath: state.modsDirectoryPath,
            selectedModSetID: state.selectedModSetID,
            selectedModSetName: state.modSetSelection.selectedSet?.name,
            appliedModSetID: state.appliedModSetID,
            subjects: subjects,
            details: details
        )

        do {
            try AuditLogStore.append(entry, to: auditLogURL)
            reloadAuditTrail(in: &state)
            state.activityMessage = ""
        } catch {
            state.auditTrail.lastErrorMessage = error.localizedDescription
        }
    }

    private func auditSubjectForInstalledMod(_ url: URL) -> AuditLogSubject {
        AuditLogSubject(
            kind: .mod,
            id: nil,
            name: url.lastPathComponent.trimmingPrefix(Character(".")),
            path: url.path
        )
    }

    private func auditSubjectForMod(
        _ mod: ModInfo,
        path: String? = nil
    ) -> AuditLogSubject {
        AuditLogSubject(
            kind: .mod,
            id: mod.id,
            name: mod.displayName,
            path: path ?? mod.url.path
        )
    }

    private func auditSubjectForModSet(_ set: ModSet) -> AuditLogSubject {
        AuditLogSubject(
            kind: .modSet,
            id: set.id,
            name: set.name,
            path: nil
        )
    }

    private func auditSubjectForFolder(_ url: URL) -> AuditLogSubject {
        AuditLogSubject(
            kind: .modsFolder,
            id: nil,
            name: url.lastPathComponent,
            path: url.path
        )
    }

    private func auditSubjectForSourceFile(_ url: URL) -> AuditLogSubject {
        AuditLogSubject(
            kind: .sourceFile,
            id: nil,
            name: url.lastPathComponent,
            path: url.path
        )
    }

    private func guardCanManageMods(in state: inout ModManagerState) -> Bool {
        switch state.readiness {
        case .needsFolderAccess:
            record(AppStrings.Status.chooseModsFolderBeforeManaging, in: &state)
            return false
        case .missingModsFolder:
            record(AppStrings.Status.modsFolderMissingChooseAgain, in: &state)
            return false
        case .ready:
            return true
        }
    }

    private func performWithFolderAccess<T>(
        state: inout ModManagerState,
        _ operation: () throws -> T
    ) throws -> T {
        do {
            let result = try folderAccess.withAccess(operation)
            lastFolderAccessError = nil
            return result
        } catch let error as SecurityScopedFolderAccessError {
            recordFolderAccessProblem(error, in: &state)
            throw error
        }
    }

    private func withFolderAccess<T>(
        state: inout ModManagerState,
        _ operation: () throws -> T
    ) -> T? {
        do {
            let result = try performWithFolderAccess(state: &state, operation)
            lastFolderAccessError = nil
            return result
        } catch is SecurityScopedFolderAccessError {
            return nil
        } catch {
            let message = error.localizedDescription
            if lastFolderAccessError != message {
                record(AppStrings.Status.couldNotRestoreSavedFolderAccess(message), in: &state)
                lastFolderAccessError = message
            }
            return nil
        }
    }

    private func recordFolderAccessProblem(
        _ error: SecurityScopedFolderAccessError,
        in state: inout ModManagerState
    ) {
        folderAccess.clearBookmark()
        state.hasSavedFolderAccess = false

        let message = AppStrings.Status.chooseModsFolderAgain(error.localizedDescription)
        if lastFolderAccessError != message {
            record(message, in: &state)
            lastFolderAccessError = message
        }
    }

    private func record(_ message: String, in state: inout ModManagerState) {
        state.activityMessage = message
    }

    private func setSelectedModSetID(_ id: String, in state: inout ModManagerState) {
        state.selectedModSetID = id
    }

    private func modSetMatchesCurrentMods(_ set: ModSet, in state: ModManagerState) -> Bool {
        let currentSnapshot = ModSetStore.snapshotSet(
            id: set.id,
            name: set.name,
            from: state.mods,
            isDefault: set.isDefault,
            isIncluded: set.isIncluded
        )
        return currentSnapshot.disabledFolderTokens == set.disabledFolderTokens
    }
}

private extension SkippedModInstallReason {
    var auditText: String {
        switch self {
        case .alreadyInstalled:
            return "already_installed"
        case .duplicateInSelection:
            return "duplicate_in_selection"
        }
    }
}
