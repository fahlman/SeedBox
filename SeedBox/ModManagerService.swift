import Foundation

actor ModManagerService {
    private let folderAccess: SecurityScopedFolderAccess
    private let modSetDirectory: URL
    private var lastFolderAccessError: String?

    init(
        folderAccess: SecurityScopedFolderAccess,
        modSetDirectory: URL = StardewInstall.defaultModSetDirectory()
    ) {
        self.folderAccess = folderAccess
        self.modSetDirectory = modSetDirectory
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
        return nextState
    }

    func chooseModsFolder(_ selectedURL: URL, from state: ModManagerState) -> ModManagerState {
        var nextState = state
        let token = SecurityScopedAccessToken(url: selectedURL)
        defer {
            token.stop()
        }

        let resolvedURL = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedURL.lastPathComponent == StardewInstall.modFolderName else {
            record("Choose the folder named \(StardewInstall.modFolderName).", in: &nextState)
            return nextState
        }

        do {
            try folderAccess.saveBookmark(for: resolvedURL)
            nextState.hasSavedFolderAccess = folderAccess.hasBookmark
            lastFolderAccessError = nil
            nextState.modsDirectoryPath = resolvedURL.path

            nextState = refreshedState(from: nextState)
            record("Selected \(resolvedURL.path).", in: &nextState)
            return nextState
        } catch {
            record("Could not save folder access: \(error.localizedDescription)", in: &nextState)
            return nextState
        }
    }

    func createModFolder(from state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard nextState.hasSavedFolderAccess else {
            record("Choose the Mods folder before creating it.", in: &nextState)
            return nextState
        }

        do {
            let currentInstall = install(for: nextState)
            try performWithFolderAccess(state: &nextState) {
                try currentInstall.createModDirectory()
            }
            record("Created \(currentInstall.modDirectoryURL.path).", in: &nextState)
            return refreshedState(from: nextState)
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record("Could not create mod folder: \(error.localizedDescription)", in: &nextState)
            return nextState
        }
    }

    func addMods(from selectedURLs: [URL], in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        guard !selectedURLs.isEmpty else {
            record("Choose one or more unzipped mod folders.", in: &nextState)
            return nextState
        }

        let sourceTokens = selectedURLs.map(SecurityScopedAccessToken.init(url:))
        defer {
            sourceTokens.forEach { $0.stop() }
        }

        do {
            let currentInstall = install(for: nextState)
            let installedURLs = try performWithFolderAccess(state: &nextState) {
                try ModLibrary.installMods(
                    from: selectedURLs,
                    into: currentInstall
                )
            }
            let changeMessage = "Added \(installedURLs.count) mod folder\(installedURLs.count == 1 ? "" : "s")."
            record(changeMessage, in: &nextState)
            nextState = refreshedState(from: nextState)
            return saveCurrentStateToSelectedModSet(
                in: nextState,
                recordingSuccess: "\(changeMessage) Updated \(nextState.modSetSelection.selectedSetName)."
            )
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record("Could not add mods: \(error.localizedDescription)", in: &nextState)
            return nextState
        }
    }

    func setMod(_ mod: ModInfo, enabled: Bool, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        do {
            _ = try performWithFolderAccess(state: &nextState) {
                try ModLibrary.setEnabled(mod, enabled: enabled)
            }
            let changeMessage = "\(enabled ? "Enabled" : "Disabled") \(mod.displayName)."
            record(changeMessage, in: &nextState)
            nextState = refreshedState(from: nextState)
            return saveCurrentStateToSelectedModSet(
                in: nextState,
                recordingSuccess: "\(changeMessage) Updated \(nextState.modSetSelection.selectedSetName)."
            )
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record("Could not update \(mod.displayName): \(error.localizedDescription)", in: &nextState)
            return nextState
        }
    }

    func deleteMod(_ mod: ModInfo, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        do {
            try performWithFolderAccess(state: &nextState) {
                try ModLibrary.trash(mod)
            }
            let changeMessage = "Moved \(mod.displayName) to the Trash."
            record(changeMessage, in: &nextState)
            nextState = refreshedState(from: nextState)
            return saveCurrentStateToSelectedModSet(
                in: nextState,
                recordingSuccess: "\(changeMessage) Updated \(nextState.modSetSelection.selectedSetName)."
            )
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record("Could not delete \(mod.displayName): \(error.localizedDescription)", in: &nextState)
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
            name: "Current",
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
            record("Created mod set \(newSet.name).", in: &nextState)
            return refreshedState(from: nextState)
        } catch {
            record("Could not create mod set: \(error.localizedDescription)", in: &nextState)
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
        guard !selectedSet.isDefault else {
            record("Default set name cannot be changed.", in: &nextState)
            return nextState
        }

        let trimmedName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            record("Set name cannot be empty.", in: &nextState)
            return nextState
        }

        let hasConflict = nextState.modSets.contains { set in
            set.id != selectedSet.id
                && set.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == trimmedName.lowercased()
        }
        if hasConflict {
            record("A mod set named \(trimmedName) already exists.", in: &nextState)
            return nextState
        }

        selectedSet.name = trimmedName

        do {
            try ModSetStore.saveSet(
                selectedSet,
                install: install(for: nextState)
            )
            record("Renamed set to \(trimmedName).", in: &nextState)
            return refreshedState(from: nextState)
        } catch {
            record("Could not rename mod set: \(error.localizedDescription)", in: &nextState)
            return nextState
        }
    }

    func selectModSet(id: String, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        guard nextState.selectedModSetID != id else {
            return nextState
        }

        guard guardCanManageMods(in: &nextState) else {
            return nextState
        }

        guard let setToApply = nextState.modSets.first(where: { $0.id == id }) else {
            record("Could not apply set: selection is missing.", in: &nextState)
            return nextState
        }

        do {
            if let previousSet = nextState.modSetSelection.selectedSet {
                try saveCurrentState(to: previousSet, in: nextState)
            }

            let changedCount = try applyModSet(setToApply, in: nextState, state: &nextState)
            setSelectedModSetID(id, in: &nextState)
            nextState.appliedModSetID = id
            record("Applied \(setToApply.name) (\(changedCount) change\(changedCount == 1 ? "" : "s")).", in: &nextState)
            return refreshedState(from: nextState)
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record("Could not apply set: \(error.localizedDescription)", in: &nextState)
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
            record("Could not delete mod set: \(error.localizedDescription)", in: &nextState)
            return nextState
        }

        guard nextState.selectedModSetID == set.id else {
            if nextState.appliedModSetID == set.id {
                nextState.appliedModSetID = nil
            }

            record("Deleted mod set \(set.name).", in: &nextState)
            return refreshedState(from: nextState)
        }

        guard let defaultSet = nextState.modSets.first(where: { $0.id == ModSetStore.defaultSetID }) else {
            setSelectedModSetID(ModSetStore.defaultSetID, in: &nextState)
            nextState.appliedModSetID = nil
            record("Deleted mod set \(set.name).", in: &nextState)
            return refreshedState(from: nextState)
        }

        do {
            let changedCount = try applyModSet(defaultSet, in: nextState, state: &nextState)
            setSelectedModSetID(ModSetStore.defaultSetID, in: &nextState)
            nextState.appliedModSetID = ModSetStore.defaultSetID
            record(
                "Deleted mod set \(set.name). Applied Default (\(changedCount) change\(changedCount == 1 ? "" : "s")).",
                in: &nextState
            )
            return refreshedState(from: nextState)
        } catch is SecurityScopedFolderAccessError {
            setSelectedModSetID(ModSetStore.defaultSetID, in: &nextState)
            nextState.appliedModSetID = nil
            record("Deleted mod set \(set.name). Choose the Mods folder again to apply Default.", in: &nextState)
            return refreshedState(from: nextState)
        } catch {
            setSelectedModSetID(ModSetStore.defaultSetID, in: &nextState)
            nextState.appliedModSetID = nil
            record("Deleted mod set \(set.name), but could not apply Default: \(error.localizedDescription)", in: &nextState)
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
            return
        }

        do {
            let currentInstall = install(for: state)
            state.mods = try performWithFolderAccess(state: &state) {
                try ModLibrary.scan(install: currentInstall)
            }
        } catch is SecurityScopedFolderAccessError {
            state.mods = []
        } catch {
            state.mods = []
            record("Could not read mods: \(error.localizedDescription)", in: &state)
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
            record("Could not read mod sets: \(error.localizedDescription)", in: &state)
        }
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

        do {
            try saveCurrentState(to: selectedSet, in: nextState)
            nextState.appliedModSetID = selectedSet.id
            record(successMessage ?? "Updated \(selectedSet.name).", in: &nextState)
            return refreshedState(from: nextState)
        } catch {
            record("Could not save mod set: \(error.localizedDescription)", in: &nextState)
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

    private func guardCanManageMods(in state: inout ModManagerState) -> Bool {
        switch state.readiness {
        case .needsFolderAccess:
            record("Choose the Mods folder before managing mods.", in: &state)
            return false
        case .missingModsFolder:
            record("The Mods folder is missing. Choose it again from Settings.", in: &state)
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
                record("Could not restore saved folder access: \(message)", in: &state)
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

        let message = "Choose the Mods folder again. \(error.localizedDescription)"
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
            isDefault: set.isDefault
        )
        return currentSnapshot.disabledFolderTokens == set.disabledFolderTokens
    }
}
