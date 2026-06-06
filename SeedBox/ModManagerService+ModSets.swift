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
            record(AppStrings.Status.couldNotSaveModSet(error.localizedDescription), in: &nextState)
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
}
