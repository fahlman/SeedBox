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

    func prepareImportPreview(from selectedURLs: [URL]) -> ModImportPreview? {
        switch importPreviewCoordinator.prepareImportPreview(
            from: selectedURLs,
            install: install,
            readiness: state.readiness
        ) {
        case .success(let preview):
            return preview
        case .failure(let outcome):
            apply(outcome)
            return nil
        }
    }

    func addMods(
        from selectedURLs: [URL],
        replacementPolicy: ModInstallReplacementPolicy = .newerOnly
    ) async {
        commit(await service.addMods(from: selectedURLs, replacementPolicy: replacementPolicy))
    }

    func addPreviewedMods(_ preview: ModImportPreview) async {
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

    func setMod(_ mod: ModInfo, enabled: Bool) async {
        commit(await service.setMod(mod, enabled: enabled))
    }

    func setMods(_ mods: [ModInfo], enabled: Bool) async {
        commit(await service.setMods(mods, enabled: enabled))
    }

    func deleteMod(_ mod: ModInfo) async {
        commit(await service.deleteMod(mod))
    }

    func restoreArchivedMods(_ archivedMods: [ArchivedModInfo]) async {
        commit(await service.restoreArchivedMods(archivedMods))
    }

    func restorePreviousVersion(of mod: ModInfo) async {
        commit(await service.restorePreviousVersion(of: mod))
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

    func createModSet(named name: String, from sourceSet: ModSet? = nil) async {
        commit(await service.createModSet(named: name, from: sourceSet))
    }

    func duplicateSelectedModSet(named name: String) async {
        commit(await service.duplicateSelectedModSet(named: name))
    }

    func renameSelectedModSet(to requestedName: String) async {
        commit(await service.renameSelectedModSet(to: requestedName))
    }

    func selectModSet(id: String) async {
        commit(await service.selectModSet(id: id))
    }

    func restoreSelectedModSet(id: String) async {
        commit(await service.restoreSelectedModSet(id: id))
    }

    func deleteModSet(_ set: ModSet) async {
        commit(await service.deleteModSet(set))
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

    private func commit(_ nextState: ModManagerState) {
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
