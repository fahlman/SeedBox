import AppKit
import Foundation

private let modManagerNotificationSenderIDKey = "senderID"

@MainActor
final class ModManagerViewModel: ObservableObject {
    static let didChangeSharedStateNotification = Notification.Name("ModManagerViewModelDidChangeSharedState")

    @Published private(set) var state: ModManagerState

    private let folderAccess: SecurityScopedFolderAccess
    private let folderChangeNotifier: ModFolderChangeNotifying
    private let instanceID = UUID()
    private let modSetDirectory: URL
    private let modsFolderMonitor: ModsFolderMonitoring
    private let preferences: ModManagerPreferences
    private let service: ModManagerService
    private var ignoredFolderChangeDeadline = Date.distantPast
    private var lastFolderAccessError: String?
    private var sharedStateObservation: NotificationObservation?

    init(
        defaults: UserDefaults = .standard,
        modSetDirectory: URL = StardewInstall.defaultModSetDirectory(),
        selectedModSetID: String = ModSetStore.defaultSetID,
        modsFolderMonitor: ModsFolderMonitoring = ModsFolderMonitor(),
        folderChangeNotifier: ModFolderChangeNotifying = UserNotificationModFolderChangeNotifier.shared
    ) {
        let folderAccess = SecurityScopedFolderAccess(defaults: defaults)
        let preferences = ModManagerPreferences(defaults: defaults)
        self.folderAccess = folderAccess
        self.folderChangeNotifier = folderChangeNotifier
        self.modSetDirectory = modSetDirectory
        self.modsFolderMonitor = modsFolderMonitor
        self.preferences = preferences
        service = ModManagerService(
            folderAccess: folderAccess,
            modSetDirectory: modSetDirectory
        )
        state = Self.initialState(
            preferences: preferences,
            folderAccess: folderAccess,
            modSetDirectory: modSetDirectory,
            selectedModSetID: selectedModSetID
        )
        self.modsFolderMonitor.onChange = { [weak self] in
            Task {
                await self?.refreshAfterObservedModsFolderChange()
            }
        }
        sharedStateObservation = NotificationObservation(token: NotificationCenter.default.addObserver(
            forName: Self.didChangeSharedStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let senderID = notification.userInfo?[modManagerNotificationSenderIDKey] as? UUID
            Task { @MainActor [weak self, senderID] in
                guard let self else {
                    return
                }

                guard senderID != self.instanceID else {
                    return
                }

                await self.refreshAfterSharedStateChange()
            }
        })
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

    var mods: [ModInfo] {
        state.mods
    }

    var selectedModSetID: String {
        state.selectedModSetID
    }

    func refresh() async {
        var nextState = stateByRestoringSavedFolder(from: state)
        if preferences.hasLastKnownModFolderTokens {
            nextState = await service.reconcileStartupModsFolderChange(
                from: nextState,
                previousModFolderTokens: preferences.lastKnownModFolderTokens,
                appliedModSetID: preferences.lastAppliedModSetID
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
        guard guardCanRevealMods() else {
            return
        }

        do {
            try performWithFolderAccess {
                NSWorkspace.shared.activateFileViewerSelecting([install.modDirectoryURL])
            }
        } catch is SecurityScopedFolderAccessError {
        } catch {
            record(AppStrings.Status.couldNotRevealModsFolder(error.localizedDescription))
        }
    }

    func revealArchivedModsFolder() {
        do {
            try FileManager.default.createDirectory(
                at: install.archivedModsDirectoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.activateFileViewerSelecting([install.archivedModsDirectoryURL])
        } catch {
            record(AppStrings.Status.couldNotRevealArchivedMods(error.localizedDescription))
        }
    }

    func revealMod(_ mod: ModInfo) {
        guard guardCanRevealMods() else {
            return
        }

        do {
            try performWithFolderAccess {
                NSWorkspace.shared.activateFileViewerSelecting([mod.url])
            }
        } catch is SecurityScopedFolderAccessError {
        } catch {
            record(AppStrings.Status.couldNotRevealMod(mod.displayName, errorDescription: error.localizedDescription))
        }
    }

    func createModFolder() async {
        ignoreObservedFolderChangesBriefly()
        commitState(await service.createModFolder(from: state))
        ignoreObservedFolderChangesBriefly()
    }

    func prepareImportPreview(from selectedURLs: [URL]) -> ModImportPreview? {
        guard guardCanRevealMods() else {
            return nil
        }

        guard !selectedURLs.isEmpty else {
            record(AppStrings.Status.chooseModFoldersOrZipArchives)
            return nil
        }

        let sourceTokens = selectedURLs.map(SecurityScopedAccessToken.init(url:))
        defer {
            sourceTokens.forEach { $0.stop() }
        }

        do {
            return try performWithFolderAccess {
                try ModLibrary.previewImport(
                    from: selectedURLs,
                    into: install
                )
            }
        } catch is SecurityScopedFolderAccessError {
            return nil
        } catch {
            record(AppStrings.Status.couldNotPreviewMods(error.localizedDescription))
            return nil
        }
    }

    func addMods(
        from selectedURLs: [URL],
        replacementPolicy: ModInstallReplacementPolicy = .newerOnly
    ) async {
        ignoreObservedFolderChangesBriefly()
        commitState(await service.addMods(
            from: selectedURLs,
            sourceCleanupSettings: preferences.sourceCleanupSettings,
            replacementPolicy: replacementPolicy,
            in: state
        ))
        ignoreObservedFolderChangesBriefly()
    }

    func addPreviewedMods(_ preview: ModImportPreview) async {
        ignoreObservedFolderChangesBriefly()
        commitState(await service.addPreviewedMods(
            preview,
            sourceCleanupSettings: preferences.sourceCleanupSettings,
            in: state
        ))
        ignoreObservedFolderChangesBriefly()
    }

    func recordAddModsSelectionError(_ error: Error) {
        record(AppStrings.Status.couldNotChooseMods(error.localizedDescription))
    }

    func keepSourceFiles(for offer: SourceCleanupOffer, remembersChoice: Bool) {
        if remembersChoice {
            preferences.moveModFilesToTrashAfterAddingMods = false
            preferences.suppressAddModsSuccessNotification = true
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
            preferences.moveModFilesToTrashAfterAddingMods = true
            preferences.suppressAddModsSuccessNotification = true
        }
        commitState(await service.moveSourceFilesToTrash(for: offer, in: state))
    }

    var sourceCleanupSettings: SourceCleanupSettings {
        preferences.sourceCleanupSettings
    }

    var archiveSettings: ArchiveSettings {
        preferences.archiveSettings
    }

    func setMoveModFilesToTrashAfterAddingMods(_ isEnabled: Bool) {
        preferences.moveModFilesToTrashAfterAddingMods = isEnabled
        objectWillChange.send()
    }

    func setSuppressAddModsSuccessNotification(_ isEnabled: Bool) {
        preferences.suppressAddModsSuccessNotification = isEnabled
        objectWillChange.send()
    }

    func setAutomaticallyPrunesExpiredArchives(_ isEnabled: Bool) {
        preferences.automaticallyPrunesExpiredArchives = isEnabled
        var nextState = state
        nextState.archiveSettings = preferences.archiveSettings
        commitState(nextState, broadcastsChange: false)
    }

    func setArchiveRetentionDays(_ days: Int) {
        preferences.archiveRetentionDays = days
        var nextState = state
        nextState.archiveSettings = preferences.archiveSettings
        commitState(nextState, broadcastsChange: false)
    }

    func setMod(_ mod: ModInfo, enabled: Bool) async {
        ignoreObservedFolderChangesBriefly()
        commitState(await service.setMod(mod, enabled: enabled, in: state))
        ignoreObservedFolderChangesBriefly()
    }

    func setMods(_ mods: [ModInfo], enabled: Bool) async {
        guard !mods.isEmpty else {
            return
        }

        ignoreObservedFolderChangesBriefly()
        var nextState = state
        for mod in mods {
            nextState = await service.setMod(mod, enabled: enabled, in: nextState)
        }
        commitState(nextState)
        ignoreObservedFolderChangesBriefly()
    }

    func deleteMod(_ mod: ModInfo) async {
        ignoreObservedFolderChangesBriefly()
        commitState(await service.deleteMod(mod, in: state))
        ignoreObservedFolderChangesBriefly()
    }

    func restoreArchivedMods(_ archivedMods: [ArchivedModInfo]) async {
        ignoreObservedFolderChangesBriefly()
        commitState(await service.restoreArchivedMods(archivedMods, in: state))
        ignoreObservedFolderChangesBriefly()
    }

    func previousArchivedVersion(for mod: ModInfo?) -> ArchivedModInfo? {
        guard let mod else {
            return nil
        }

        return ModArchive.previousVersion(for: mod, in: state.archivedMods)
    }

    func restorePreviousVersion(of mod: ModInfo) async {
        guard let archivedMod = previousArchivedVersion(for: mod) else {
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
        ignoreObservedFolderChangesBriefly()
        commitState(await service.selectModSet(id: id, in: state))
        ignoreObservedFolderChangesBriefly()
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
        ignoreObservedFolderChangesBriefly()
        commitState(await service.deleteModSet(set, in: state))
        ignoreObservedFolderChangesBriefly()
    }

    private func guardCanRevealMods() -> Bool {
        switch state.readiness {
        case .needsFolderAccess:
            record(AppStrings.Status.chooseModsFolderBeforeManaging)
            return false
        case .missingModsFolder:
            record(AppStrings.Status.modsFolderMissingChooseAgain)
            return false
        case .ready:
            return true
        }
    }

    private func performWithFolderAccess<T>(_ operation: () throws -> T) throws -> T {
        do {
            let result = try folderAccess.withAccess(operation)
            lastFolderAccessError = nil
            return result
        } catch let error as SecurityScopedFolderAccessError {
            recordFolderAccessProblem(error)
            throw error
        }
    }

    private func recordFolderAccessProblem(_ error: SecurityScopedFolderAccessError) {
        folderAccess.clearBookmark()
        state.hasSavedFolderAccess = false

        let message = AppStrings.Status.chooseModsFolderAgain(error.localizedDescription)
        if lastFolderAccessError != message {
            record(message)
            lastFolderAccessError = message
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
            NotificationCenter.default.post(
                name: Self.didChangeSharedStateNotification,
                object: nil,
                userInfo: [modManagerNotificationSenderIDKey: instanceID]
            )
        }
    }

    private func ignoreObservedFolderChangesBriefly() {
        ignoredFolderChangeDeadline = Date().addingTimeInterval(2)
    }

    private func refreshAfterObservedModsFolderChange() async {
        guard state.readiness.canManageMods else {
            updateModsFolderMonitor()
            return
        }

        guard Date() >= ignoredFolderChangeDeadline else {
            return
        }

        let reconciledState = await service.reconcileObservedModsFolderChange(from: state)
        commitState(reconciledState)
        folderChangeNotifier.notifyModsFolderChanged()
    }

    private func refreshAfterSharedStateChange() async {
        var nextState = stateByRestoringSavedFolder(from: state)
        nextState = await service.refreshedState(from: nextState)
        commitState(nextState, broadcastsChange: false)
    }

    private func updateModsFolderMonitor() {
        guard state.readiness.canManageMods else {
            modsFolderMonitor.stopWatching()
            return
        }

        let modsDirectoryURL = install.modDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard modsFolderMonitor.watchedPath != modsDirectoryURL.path else {
            return
        }

        do {
            let accessToken = try folderAccess.beginAccess()
            try modsFolderMonitor.startWatching(
                modsDirectoryURL,
                securityScopedAccess: accessToken
            )
        } catch {
            modsFolderMonitor.stopWatching()
            record(AppStrings.Status.couldNotWatchModsFolder(error.localizedDescription))
        }
    }

    private func persistPreferences() {
        preferences.save(state)
    }

    private static func initialState(
        preferences: ModManagerPreferences,
        folderAccess: SecurityScopedFolderAccess,
        modSetDirectory: URL,
        selectedModSetID: String
    ) -> ModManagerState {
        let defaultModsPath = StardewInstall.defaultModsDirectory().path
        let bookmarkedDirectoryPath = try? folderAccess.resolveBookmarkURL()?.path
        let savedDirectoryPath = preferences.modsDirectoryPath
        let initialDirectoryPath = bookmarkedDirectoryPath ?? savedDirectoryPath ?? defaultModsPath
        let install = StardewInstall(
            modsDirectory: URL(fileURLWithPath: initialDirectoryPath, isDirectory: true),
            modSetDirectory: modSetDirectory
        )

        return ModManagerState(
            modsDirectoryPath: initialDirectoryPath,
            status: install.status(),
            hasSavedFolderAccess: folderAccess.hasBookmark,
            mods: [],
            invalidModFolders: [],
            archivedMods: [],
            archiveSummary: ModArchiveSummary(),
            archiveSettings: preferences.archiveSettings,
            hasLoadedMods: false,
            modSets: [],
            selectedModSetID: selectedModSetID,
            appliedModSetID: nil,
            activityMessage: "",
            auditTrail: AuditTrailState(
                logPath: StardewInstall.auditLogURL(forModSetDirectory: modSetDirectory).path,
                recentEntries: [],
                lastErrorMessage: nil
            ),
            pendingSourceCleanupOffer: nil
        )
    }

    private func stateByRestoringSavedFolder(from currentState: ModManagerState) -> ModManagerState {
        let bookmarkedDirectoryPath = try? folderAccess.resolveBookmarkURL()?.path
        let restoredDirectoryPath = bookmarkedDirectoryPath
            ?? preferences.modsDirectoryPath
            ?? currentState.modsDirectoryPath
        let install = StardewInstall(
            modsDirectory: URL(fileURLWithPath: restoredDirectoryPath, isDirectory: true),
            modSetDirectory: modSetDirectory
        )

        var nextState = currentState
        nextState.modsDirectoryPath = restoredDirectoryPath
        nextState.hasSavedFolderAccess = folderAccess.hasBookmark
        nextState.status = install.status()
        return nextState
    }
}

private final class NotificationObservation: @unchecked Sendable {
    private let token: any NSObjectProtocol

    init(token: any NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
