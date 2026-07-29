import Foundation
import Observation

@MainActor
@Observable
final class ModManagerViewModel {
    /// The one production instance, shared by every scene so all windows
    /// observe the same canonical state. Tests construct isolated instances.
    static let shared = ModManagerViewModel()

    private(set) var state: ModManagerState

    @ObservationIgnored private let importPreviewCoordinator: ModImportPreviewCoordinator
    @ObservationIgnored private let modSetDirectory: URL
    @ObservationIgnored private let service: ModManagerService
    @ObservationIgnored private let workspacePresenter: ModManagerWorkspacePresenter
    @ObservationIgnored private var folderObservation: ModManagerFolderObservation?

    init(
        defaults: UserDefaults = .standard,
        modSetDirectory: URL = StardewInstall.defaultModSetDirectory(),
        selectedModSetID: String = ModSetStore.defaultSetID,
        modsFolderMonitor: ModsFolderMonitoring = ModsFolderMonitor(),
        folderChangeNotifier: ModFolderChangeNotifying = UserNotificationModFolderChangeNotifier.shared,
        updateChecker: ModUpdateChecking = SMAPIModUpdateClient()
    ) {
        let folderAccess = SecurityScopedFolderAccess(defaults: defaults)
        let smapiLogFolderAccess = SecurityScopedFolderAccess(
            defaults: defaults,
            bookmarkKey: "smapiLogFolderBookmarkData"
        )
        let preferences = ModManagerPreferences(defaults: defaults)
        let stateStore = ModManagerStateStore(
            folderAccess: folderAccess,
            modSetDirectory: modSetDirectory,
            preferences: preferences
        )
        let initialState = stateStore.initialState(selectedModSetID: selectedModSetID)
        state = initialState
        importPreviewCoordinator = ModImportPreviewCoordinator(folderAccess: folderAccess)
        self.modSetDirectory = modSetDirectory
        service = ModManagerService(
            folderAccess: folderAccess,
            smapiLogFolderAccess: smapiLogFolderAccess,
            stateStore: stateStore,
            initialState: initialState,
            modSetDirectory: modSetDirectory,
            updateChecker: updateChecker
        )
        workspacePresenter = ModManagerWorkspacePresenter(folderAccess: folderAccess)
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

    var sourceCleanupSettings: SourceCleanupSettings {
        state.sourceCleanupSettings
    }

    var archiveSettings: ArchiveSettings {
        state.archiveSettings
    }

    func refresh() async {
        commit(await service.refresh())
    }

    func refreshAfterActivation() async {
        commit(await service.refreshAfterActivation())
    }

    func chooseModsFolder(_ selectedURL: URL) async {
        commit(await service.chooseModsFolder(selectedURL))
    }

    func recordModsFolderSelectionError(_ error: Error) {
        record(AppStrings.Status.couldNotChooseModsFolder(error.localizedDescription), severity: .error)
    }

    func revealModsFolder() {
        apply(workspacePresenter.revealModsFolder(readiness: state.readiness, install: install))
    }

    func revealArchivedModsFolder() {
        apply(workspacePresenter.revealArchivedModsFolder(install: install))
    }

    func revealMod(_ mod: ModInfo) {
        apply(workspacePresenter.revealMod(mod, readiness: state.readiness))
    }

    func createModFolder() async {
        commit(await service.createModFolder())
    }

    func prepareImportPreview(from selectedURLs: [URL]) async -> ModImportPreviewResult {
        let result = await importPreviewCoordinator.prepareImportPreview(
            from: selectedURLs,
            install: install,
            readiness: state.readiness
        )

        switch result {
        case .success(let preview):
            return .success(preview)
        case .failure(let outcome):
            apply(outcome)
            return .failure(outcome)
        }
    }

    func addMods(
        from selectedURLs: [URL],
        replacementPolicy: ModInstallReplacementPolicy = .newerOnly
    ) async {
        commit(await service.addMods(from: selectedURLs, replacementPolicy: replacementPolicy))
    }

    func addPreviewedMods(_ session: ModImportPreviewSession) async {
        guard let preview = session.takeForInstallation() else {
            return
        }
        commit(await service.addPreviewedMods(preview))
    }

    func recordAddModsSelectionError(_ error: Error) {
        record(AppStrings.Status.couldNotChooseMods(error.localizedDescription), severity: .error)
    }

    func keepSourceFiles(for offer: SourceCleanupOffer, remembersChoice: Bool) async {
        commit(await service.keepSourceFiles(for: offer, remembersChoice: remembersChoice))
    }

    func dismissSourceCleanupOffer() async {
        commit(await service.dismissSourceCleanupOffer())
    }

    func moveSourceFilesToTrash(
        for offer: SourceCleanupOffer,
        remembersChoice: Bool = false
    ) async {
        commit(await service.moveSourceFilesToTrash(for: offer, remembersChoice: remembersChoice))
    }

    func setMoveModFilesToTrashAfterAddingMods(_ isEnabled: Bool) async {
        commit(await service.setMoveModFilesToTrashAfterAddingMods(isEnabled))
    }

    func setSuppressAddModsSuccessNotification(_ isEnabled: Bool) async {
        commit(await service.setSuppressAddModsSuccessNotification(isEnabled))
    }

    func setAutomaticallyPrunesExpiredArchives(_ isEnabled: Bool) async {
        commit(await service.setAutomaticallyPrunesExpiredArchives(isEnabled))
    }

    func setArchiveRetentionDays(_ days: Int) async {
        commit(await service.setArchiveRetentionDays(days))
    }

    func setChecksForModUpdates(_ isEnabled: Bool) async {
        commit(await service.setChecksForModUpdates(isEnabled))
    }

    func checkForModUpdates() async {
        commit(await service.recordActivity(AppStrings.Status.checkingForModUpdates))
        commit(await service.checkForModUpdates())
    }

    @discardableResult
    func setMod(_ mod: ModInfo, enabled: Bool) async -> Bool {
        await setMod(id: mod.id, enabled: enabled)
    }

    @discardableResult
    func setMod(
        id: ModInfo.ID,
        enabled: Bool,
        ifCurrently expectedEnabled: Bool? = nil
    ) async -> Bool {
        let result = await service.setModResult(
            id: id,
            enabled: enabled,
            expectedEnabled: expectedEnabled
        )
        commit(result.state)
        return result.value
    }

    @discardableResult
    func setMods(_ mods: [ModInfo], enabled: Bool) async -> [ModEnabledStateMutation] {
        await setMods(ids: mods.map(\.id), enabled: enabled)
    }

    @discardableResult
    func setMods(
        ids: [ModInfo.ID],
        enabled: Bool,
        ifCurrently expectedStates: [ModInfo.ID: Bool]? = nil
    ) async -> [ModEnabledStateMutation] {
        let result = await service.setModsResult(
            ids: ids,
            enabled: enabled,
            expectedStates: expectedStates
        )
        commit(result.state)
        return result.value
    }

    @discardableResult
    func deleteMod(_ mod: ModInfo) async -> Bool {
        let result = await service.deleteModResult(id: mod.id)
        commit(result.state)
        return result.value
    }

    @discardableResult
    func restoreArchivedMods(_ archivedMods: [ArchivedModInfo]) async -> [String] {
        let result = await service.restoreArchivedModsResult(ids: archivedMods.map(\.id))
        commit(result.state)
        return result.value
    }

    func deleteArchivedMods(_ archivedMods: [ArchivedModInfo]) async {
        commit(await service.deleteArchivedMods(ids: archivedMods.map(\.id)))
    }

    func restorePreviousVersion(of mod: ModInfo) async {
        commit(await service.restorePreviousVersion(ofModWithID: mod.id))
    }

    func pruneExpiredArchives() async {
        commit(await service.pruneExpiredArchives())
    }

    func resolveDuplicateGroup(id: String) async {
        commit(await service.resolveDuplicateGroup(id: id))
    }

    func chooseSMAPILogFolder(_ selectedURL: URL) async {
        commit(await service.chooseSMAPILogFolder(selectedURL))
    }

    func recordSMAPILogFolderSelectionError(_ error: Error) {
        record(AppStrings.Status.couldNotChooseLogFolder(error.localizedDescription), severity: .error)
    }

    func dismissLastSessionNotice() async {
        commit(await service.dismissLastSessionNotice())
    }

    func startBisection() async {
        commit(await service.startBisection())
    }

    func recordBisectionResult(problemOccurred: Bool) async {
        commit(await service.recordBisectionResult(problemOccurred: problemOccurred))
    }

    func cancelBisection() async {
        commit(await service.cancelBisection())
    }

    @discardableResult
    func createModSet(
        named name: String,
        from sourceSet: ModSet? = nil,
        parentID: String? = nil
    ) async -> ModSet? {
        let result = await service.createModSetResult(
            named: name,
            from: sourceSet,
            parentID: parentID
        )
        commit(result.state)
        return result.value
    }

    @discardableResult
    func duplicateSelectedModSet(named name: String, parentID: String? = nil) async -> ModSet? {
        let result = await service.duplicateSelectedModSetResult(
            named: name,
            parentID: parentID
        )
        commit(result.state)
        return result.value
    }

    @discardableResult
    func renameSelectedModSet(to requestedName: String) async -> Bool {
        guard let selectedSet = state.modSetSelection.selectedSet else {
            return false
        }
        return await renameModSet(
            id: selectedSet.id,
            to: requestedName
        )
    }

    @discardableResult
    func renameModSet(
        id: ModSet.ID,
        to requestedName: String,
        ifNamed expectedName: String? = nil
    ) async -> Bool {
        let result = await service.renameModSetResult(
            id: id,
            to: requestedName,
            expectedName: expectedName
        )
        commit(result.state)
        return result.value
    }

    @discardableResult
    func selectModSet(
        id: String,
        ifCurrentlySelected expectedSetID: String? = nil
    ) async -> Bool {
        let result = await service.selectModSetResult(
            id: id,
            expectedSelectedSetID: expectedSetID
        )
        commit(result.state)
        return result.value
    }

    func restoreSelectedModSet(id: String) async {
        commit(await service.restoreSelectedModSet(id: id))
    }

    @discardableResult
    func deleteModSet(_ set: ModSet) async -> Bool {
        let result = await service.deleteModSetResult(id: set.id)
        commit(result.state)
        return result.value
    }

    @discardableResult
    func restoreModSet(_ set: ModSet) async -> Bool {
        let result = await service.restoreModSetResult(set)
        commit(result.state)
        return result.value
    }

    func importModSet(fromFileAt url: URL) async {
        commit(await service.importModSet(fromFileAt: url))
    }

    /// The export bytes for the selected Mod Set, or nil when no editable set is
    /// selected. The view writes these to a user-chosen `.seedboxset` file.
    func exportDataForSelectedModSet() -> Data? {
        guard let selectedSet = state.modSetSelection.selectedSet else {
            return nil
        }
        return try? ModSetTransfer.exportData(
            for: selectedSet,
            mods: state.mods,
            in: state.modSets
        )
    }

    func exportSelectedModSet(to url: URL) async {
        guard let selectedSet = state.modSetSelection.selectedSet else {
            return
        }

        let mods = state.mods
        let modSets = state.modSets
        let token = SecurityScopedAccessToken(url: url)
        defer {
            token.stop()
        }

        do {
            try await Task.detached(priority: .userInitiated) {
                try ModSetTransfer.write(
                    selectedSet,
                    mods: mods,
                    in: modSets,
                    to: url
                )
            }.value
            commit(
                await service.recordActivity(
                    AppStrings.Status.exportedModSet(selectedSet.name)
                )
            )
        } catch {
            commit(
                await service.recordActivity(
                    AppStrings.Status.couldNotExportModSet(error.localizedDescription),
                    severity: .error
                )
            )
        }
    }

    /// A shareable item for the selected Mod Set, or nil when none is selected,
    /// for use with the macOS share sheet.
    func exportableSelectedModSet() -> ExportableModSet? {
        guard let selectedSet = state.modSetSelection.selectedSet else {
            return nil
        }
        return ExportableModSet.make(for: selectedSet, mods: state.mods, in: state.modSets)
    }

    private func record(_ message: String, severity: StatusEvent.Severity = .info) {
        Task {
            commit(await service.recordActivity(message, severity: severity))
        }
    }

    private func apply(_ outcome: WorkspaceActionOutcome) {
        switch outcome {
        case .completed:
            break
        case .recorded(let event):
            record(event.message, severity: event.severity)
        case .folderAccessLost(let message):
            Task {
                commit(await service.noteFolderAccessLost(message: message))
            }
        }
    }

    func commit(_ nextState: ModManagerState) {
        guard nextState.revision >= state.revision else {
            return
        }
        state = nextState
        updateModsFolderMonitor()
    }

    private func refreshAfterObservedModsFolderChange() async {
        guard state.readiness.canManageMods else {
            updateModsFolderMonitor()
            return
        }

        let (reconciledState, didObserveExternalChange) = await service.reconcileObservedModsFolderChange()
        commit(reconciledState)
        if didObserveExternalChange {
            folderObservation?.notifyObservedChange()
        }
    }

    private func updateModsFolderMonitor() {
        guard let message = folderObservation?.synchronizeWatching(for: state, install: install),
              message != state.activityMessage
        else {
            return
        }

        record(message, severity: .error)
    }
}
