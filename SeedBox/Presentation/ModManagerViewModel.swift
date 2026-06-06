import Foundation

@MainActor
final class ModManagerViewModel: ObservableObject {
    @Published private(set) var state: ModManagerState

    private let importPreviewCoordinator: ModImportPreviewCoordinator
    private let modSetDirectory: URL
    private let service: ModManagerService
    private let workspacePresenter: ModManagerWorkspacePresenter
    private var folderObservation: ModManagerFolderObservation?
    private var stateStore: ModManagerStateStore
    private var sharedStateSync: ModManagerSharedStateSync?

    init(
        defaults: UserDefaults = .standard,
        modSetDirectory: URL = StardewInstall.defaultModSetDirectory(),
        selectedModSetID: String = ModSetStore.defaultSetID,
        modsFolderMonitor: ModsFolderMonitoring = ModsFolderMonitor(),
        folderChangeNotifier: ModFolderChangeNotifying = UserNotificationModFolderChangeNotifier.shared
    ) {
        let folderAccess = SecurityScopedFolderAccess(defaults: defaults)
        let preferences = ModManagerPreferences(defaults: defaults)
        let stateStore = ModManagerStateStore(
            folderAccess: folderAccess,
            modSetDirectory: modSetDirectory,
            preferences: preferences
        )
        importPreviewCoordinator = ModImportPreviewCoordinator(folderAccess: folderAccess)
        self.modSetDirectory = modSetDirectory
        self.stateStore = stateStore
        service = ModManagerService(
            folderAccess: folderAccess,
            modSetDirectory: modSetDirectory
        )
        workspacePresenter = ModManagerWorkspacePresenter(folderAccess: folderAccess)
        state = stateStore.initialState(selectedModSetID: selectedModSetID)
        folderObservation = ModManagerFolderObservation(
            folderAccess: folderAccess,
            monitor: modsFolderMonitor,
            notifier: folderChangeNotifier
        ) { [weak self] in
            guard let self else {
                return
            }

            await self.refreshAfterObservedModsFolderChange()
        }
        sharedStateSync = ModManagerSharedStateSync { [weak self] in
            guard let self else {
                return
            }

            await self.refreshAfterSharedStateChange()
        }
        updateModsFolderMonitor()
    }

    var install: StardewInstall {
        StardewInstall(
            modsDirectory: URL(fileURLWithPath: state.modsDirectoryPath, isDirectory: true),
            modSetDirectory: modSetDirectory
        )
    }

    var modFolderName: String {
        StardewInstall.modFolderName
    }

    func refresh() async {
        var nextState = stateStore.stateByRestoringSavedFolder(from: state)
        if stateStore.hasLastKnownModFolderTokens {
            nextState = await service.reconcileStartupModsFolderChange(
                from: nextState,
                previousModFolderTokens: stateStore.lastKnownModFolderTokens,
                appliedModSetID: stateStore.lastAppliedModSetID
            )
        } else {
            nextState = await service.refreshedState(from: nextState)
        }
        commitState(nextState, broadcastsChange: false)
    }

    func chooseModsFolder(_ selectedURL: URL) async {
        commitState(await service.chooseModsFolder(selectedURL, from: state))
    }

    func recordModsFolderSelectionError(_ error: Error) {
        record(AppStrings.Status.couldNotChooseModsFolder(error.localizedDescription))
    }

    func revealModsFolder() {
        commitState(
            workspacePresenter.revealModsFolder(in: state, install: install),
            broadcastsChange: false
        )
    }

    func revealArchivedModsFolder() {
        commitState(
            workspacePresenter.revealArchivedModsFolder(in: state, install: install),
            broadcastsChange: false
        )
    }

    func revealMod(_ mod: ModInfo) {
        commitState(
            workspacePresenter.revealMod(mod, in: state),
            broadcastsChange: false
        )
    }

    func createModFolder() async {
        await commitFolderMutation {
            await service.createModFolder(from: state)
        }
    }

    func prepareImportPreview(from selectedURLs: [URL]) -> ModImportPreview? {
        switch importPreviewCoordinator.prepareImportPreview(
            from: selectedURLs,
            install: install,
            state: state
        ) {
        case .success(let preview, let nextState):
            commitState(nextState, broadcastsChange: false)
            return preview
        case .failure(let nextState):
            commitState(nextState, broadcastsChange: false)
            return nil
        }
    }

    func addMods(
        from selectedURLs: [URL],
        replacementPolicy: ModInstallReplacementPolicy = .newerOnly
    ) async {
        await commitFolderMutation {
                await service.addMods(
                    from: selectedURLs,
                    sourceCleanupSettings: stateStore.sourceCleanupSettings,
                    replacementPolicy: replacementPolicy,
                    in: state
                )
        }
    }

    func addPreviewedMods(_ preview: ModImportPreview) async {
        await commitFolderMutation {
            await service.addPreviewedMods(
                preview,
                sourceCleanupSettings: stateStore.sourceCleanupSettings,
                in: state
            )
        }
    }

    func recordAddModsSelectionError(_ error: Error) {
        record(AppStrings.Status.couldNotChooseMods(error.localizedDescription))
    }

    func keepSourceFiles(for offer: SourceCleanupOffer, remembersChoice: Bool) {
        if remembersChoice {
            stateStore.moveModFilesToTrashAfterAddingMods = false
            stateStore.suppressAddModsSuccessNotification = true
        }
        dismissSourceCleanupOffer()
    }

    func dismissSourceCleanupOffer() {
        guard state.pendingSourceCleanupOffer != nil else {
            return
        }

        var nextState = state
        nextState.pendingSourceCleanupOffer = nil
        commitState(nextState, broadcastsChange: false)
    }

    func moveSourceFilesToTrash(
        for offer: SourceCleanupOffer,
        remembersChoice: Bool = false
    ) async {
        if remembersChoice {
            stateStore.moveModFilesToTrashAfterAddingMods = true
            stateStore.suppressAddModsSuccessNotification = true
        }
        commitState(await service.moveSourceFilesToTrash(for: offer, in: state))
    }

    var sourceCleanupSettings: SourceCleanupSettings {
        stateStore.sourceCleanupSettings
    }

    var archiveSettings: ArchiveSettings {
        stateStore.archiveSettings
    }

    func setMoveModFilesToTrashAfterAddingMods(_ isEnabled: Bool) {
        stateStore.moveModFilesToTrashAfterAddingMods = isEnabled
        objectWillChange.send()
    }

    func setSuppressAddModsSuccessNotification(_ isEnabled: Bool) {
        stateStore.suppressAddModsSuccessNotification = isEnabled
        objectWillChange.send()
    }

    func setAutomaticallyPrunesExpiredArchives(_ isEnabled: Bool) {
        stateStore.automaticallyPrunesExpiredArchives = isEnabled
        var nextState = state
        nextState.archiveSettings = stateStore.archiveSettings
        commitState(nextState, broadcastsChange: false)
    }

    func setArchiveRetentionDays(_ days: Int) {
        stateStore.archiveRetentionDays = days
        var nextState = state
        nextState.archiveSettings = stateStore.archiveSettings
        commitState(nextState, broadcastsChange: false)
    }

    func setMod(_ mod: ModInfo, enabled: Bool) async {
        await commitFolderMutation {
            await service.setMod(mod, enabled: enabled, in: state)
        }
    }

    func setMods(_ mods: [ModInfo], enabled: Bool) async {
        await commitFolderMutation {
            await service.setMods(mods, enabled: enabled, in: state)
        }
    }

    func deleteMod(_ mod: ModInfo) async {
        await commitFolderMutation {
            await service.deleteMod(mod, in: state)
        }
    }

    func restoreArchivedMods(_ archivedMods: [ArchivedModInfo]) async {
        await commitFolderMutation {
            await service.restoreArchivedMods(archivedMods, in: state)
        }
    }

    func restorePreviousVersion(of mod: ModInfo) async {
        guard let archivedMod = ModArchive.previousVersion(for: mod, in: state.archivedMods) else {
            record(AppStrings.Status.noPreviousVersionAvailable(mod.displayName))
            return
        }

        await restoreArchivedMods([archivedMod])
    }

    func pruneExpiredArchives() async {
        commitState(await service.pruneExpiredArchives(in: state))
    }

    func createModSet(named name: String, from sourceSet: ModSet? = nil) async {
        commitState(await service.createModSet(named: name, from: sourceSet, in: state))
    }

    func duplicateSelectedModSet(named name: String) async {
        commitState(await service.duplicateSelectedModSet(named: name, in: state))
    }

    func renameSelectedModSet(to requestedName: String) async {
        commitState(await service.renameSelectedModSet(to: requestedName, in: state))
    }

    func selectModSet(id: String) async {
        await commitFolderMutation {
            await service.selectModSet(id: id, in: state)
        }
    }

    func restoreSelectedModSet(id: String) {
        guard state.selectedModSetID != id else {
            return
        }

        var nextState = state
        nextState.selectedModSetID = id
        commitState(nextState, broadcastsChange: false)
    }

    func deleteModSet(_ set: ModSet) async {
        await commitFolderMutation {
            await service.deleteModSet(set, in: state)
        }
    }

    private func record(_ message: String) {
        state.activityMessage = message
    }

    private func commitState(_ nextState: ModManagerState, broadcastsChange: Bool = true) {
        state = nextState
        persistPreferences()
        updateModsFolderMonitor()

        if broadcastsChange {
            sharedStateSync?.broadcastChange()
        }
    }

    private func commitFolderMutation(_ mutation: () async -> ModManagerState) async {
        folderObservation?.ignoreChangesBriefly()
        let nextState = await mutation()
        commitState(nextState)
        folderObservation?.ignoreChangesBriefly()
    }

    private func refreshAfterObservedModsFolderChange() async {
        guard state.readiness.canManageMods else {
            updateModsFolderMonitor()
            return
        }

        guard folderObservation?.shouldHandleObservedChange ?? false else {
            return
        }

        let reconciledState = await service.reconcileObservedModsFolderChange(from: state)
        commitState(reconciledState)
        folderObservation?.notifyObservedChange()
    }

    private func refreshAfterSharedStateChange() async {
        var nextState = stateStore.stateByRestoringSavedFolder(from: state)
        nextState = await service.refreshedState(from: nextState)
        commitState(nextState, broadcastsChange: false)
    }

    private func updateModsFolderMonitor() {
        if let message = folderObservation?.synchronizeWatching(for: state, install: install) {
            record(message)
        }
    }

    private func persistPreferences() {
        stateStore.save(state)
    }
}
