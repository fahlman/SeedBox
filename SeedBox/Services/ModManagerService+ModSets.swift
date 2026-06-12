import Foundation

extension ModManagerService {
    func saveCurrentStateToSelectedModSet(
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
            record(AppStrings.Status.couldNotSaveModSet(error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func applyModSet(
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

    func saveCurrentState(to set: ModSet, in state: ModManagerState) throws {
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

    func saveCurrentStateIfEditable(to set: ModSet, in state: ModManagerState) throws {
        guard set.isUserEditable else {
            return
        }

        try saveCurrentState(to: set, in: state)
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
            record(AppStrings.Status.couldNotCreateModSet(error.localizedDescription), severity: .error, in: &nextState)
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
            record(AppStrings.Errors.duplicateModSetName(trimmedName), severity: .error, in: &nextState)
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
            record(AppStrings.Status.couldNotRenameModSet(error.localizedDescription), severity: .error, in: &nextState)
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
            record(AppStrings.Status.couldNotApplySetSelectionMissing, severity: .error, in: &nextState)
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
            record(AppStrings.Status.couldNotApplySet(error.localizedDescription), severity: .error, in: &nextState)
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
            record(AppStrings.Status.couldNotDeleteModSet(error.localizedDescription), severity: .error, in: &nextState)
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
