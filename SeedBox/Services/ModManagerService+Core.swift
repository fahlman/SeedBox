import Foundation

extension ModManagerService {
    func install(for state: ModManagerState) -> StardewInstall {
        StardewInstall(
            modsDirectory: URL(fileURLWithPath: state.modsDirectoryPath, isDirectory: true),
            modSetDirectory: modSetDirectory
        )
    }

    func shouldEnableAddedMods(in state: ModManagerState) -> Bool {
        shouldEnableAddedMods(appliedModSetID: state.appliedModSetID)
    }

    func shouldEnableAddedMods(appliedModSetID: String?) -> Bool {
        appliedModSetID != ModSetStore.noneSetID
    }

    func guardCanManageMods(in state: inout ModManagerState) -> Bool {
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

    func performWithFolderAccess<T>(
        state: inout ModManagerState,
        _ operation: () throws -> T
    ) throws -> T {
        try folderAccessCoordinator.perform(state: &state, operation)
    }

    func withFolderAccess<T>(
        state: inout ModManagerState,
        _ operation: () throws -> T
    ) -> T? {
        folderAccessCoordinator.performIfAvailable(state: &state, operation)
    }

    func record(_ message: String, in state: inout ModManagerState) {
        state.activityMessage = message
    }

    func setSelectedModSetID(_ id: String, in state: inout ModManagerState) {
        state.selectedModSetID = id
    }

    func modSetMatchesCurrentMods(_ set: ModSet, in state: ModManagerState) -> Bool {
        let currentSnapshot = ModSetStore.snapshotSet(
            id: set.id,
            name: set.name,
            from: state.mods,
            isDefault: set.isDefault,
            isIncluded: set.isIncluded
        )
        return currentSnapshot.disabledFolderTokens == set.disabledFolderTokens
    }

    func standardizedPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
