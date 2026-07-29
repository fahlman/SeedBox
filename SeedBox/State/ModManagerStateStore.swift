import Foundation
import Synchronization

// UserDefaults and the bookmark store are both thread-safe; this value is
// handed to the service actor, which owns persistence from then on.
final class ModManagerStateStore: @unchecked Sendable {
    private let folderAccess: SecurityScopedFolderAccess
    private let modSetDirectory: URL
    private let smartModSetStoreURL: URL
    private let preferences: ModManagerPreferences
    private let canSaveUserSmartModSets = Mutex(true)

    init(
        folderAccess: SecurityScopedFolderAccess,
        modSetDirectory: URL,
        smartModSetStoreURL: URL? = nil,
        preferences: ModManagerPreferences
    ) {
        self.folderAccess = folderAccess
        self.modSetDirectory = modSetDirectory
        self.smartModSetStoreURL = smartModSetStoreURL
            ?? StardewInstall.smartModSetStoreURL(forModSetDirectory: modSetDirectory)
        self.preferences = preferences
    }

    var hasLastKnownModFolderTokens: Bool {
        preferences.hasLastKnownModFolderTokens
    }

    var lastKnownModFolderTokens: Set<String> {
        preferences.lastKnownModFolderTokens
    }

    var lastAppliedModSetID: String? {
        preferences.lastAppliedModSetID
    }

    var sourceCleanupSettings: SourceCleanupSettings {
        preferences.sourceCleanupSettings
    }

    var archiveSettings: ArchiveSettings {
        preferences.archiveSettings
    }

    var moveModFilesToTrashAfterAddingMods: Bool {
        get {
            preferences.moveModFilesToTrashAfterAddingMods
        }
        set {
            preferences.moveModFilesToTrashAfterAddingMods = newValue
        }
    }

    var suppressAddModsSuccessNotification: Bool {
        get {
            preferences.suppressAddModsSuccessNotification
        }
        set {
            preferences.suppressAddModsSuccessNotification = newValue
        }
    }

    var automaticallyPrunesExpiredArchives: Bool {
        get {
            preferences.automaticallyPrunesExpiredArchives
        }
        set {
            preferences.automaticallyPrunesExpiredArchives = newValue
        }
    }

    var archiveRetentionDays: Int {
        get {
            preferences.archiveRetentionDays
        }
        set {
            preferences.archiveRetentionDays = newValue
        }
    }

    var checksForModUpdates: Bool {
        get {
            preferences.checksForModUpdates
        }
        set {
            preferences.checksForModUpdates = newValue
        }
    }

    var announcedLogSessionDate: Date? {
        get {
            preferences.announcedLogSessionDate
        }
        set {
            preferences.announcedLogSessionDate = newValue
        }
    }

    func save(_ state: ModManagerState) {
        preferences.save(state)
        saveUserSmartModSetsIfNeeded(state.userSmartModSets)
    }

    private func saveUserSmartModSetsIfNeeded(_ userSmartModSets: [UserSmartModSet]) {
        guard canSaveUserSmartModSets.withLock({ $0 }) else {
            return
        }

        let storeExists = FileManager.default.fileExists(atPath: smartModSetStoreURL.path)
        guard !userSmartModSets.isEmpty || storeExists else {
            return
        }

        do {
            try UserSmartModSetStore.saveSmartModSets(userSmartModSets, to: smartModSetStoreURL)
        } catch {
            AppLog.smartModSets.error("Could not save user saved searches: \(error.localizedDescription, privacy: .private)")
        }
    }

    func initialState(selectedModSetID: String) -> ModManagerState {
        let defaultModsPath = StardewInstall.defaultModsDirectory().path
        let bookmarkedDirectoryPath = try? folderAccess.resolveBookmarkURL()?.path
        let savedDirectoryPath = preferences.modsDirectoryPath
        let initialDirectoryPath = bookmarkedDirectoryPath ?? savedDirectoryPath ?? defaultModsPath
        let install = StardewInstall(
            modsDirectory: URL(fileURLWithPath: initialDirectoryPath, isDirectory: true),
            modSetDirectory: modSetDirectory
        )
        let smartModSetLoad = loadUserSmartModSets()

        return ModManagerState(
            modsDirectoryPath: initialDirectoryPath,
            status: install.status(),
            hasSavedFolderAccess: folderAccess.hasBookmark,
            mods: [],
            invalidModFolders: [],
            archivedMods: [],
            archiveSummary: ModArchiveSummary(),
            archiveSettings: preferences.archiveSettings,
            sourceCleanupSettings: preferences.sourceCleanupSettings,
            checksForModUpdates: preferences.checksForModUpdates,
            availableUpdates: [],
            hasLoadedMods: false,
            modSets: [],
            userSmartModSets: smartModSetLoad.smartModSets,
            selectedModSetID: selectedModSetID,
            appliedModSetID: nil,
            activityStatus: smartModSetLoad.issue.map {
                StatusEvent(severity: .error, message: $0.detail)
            },
            bisectionSession: preferences.bisectionSession,
            auditTrail: AuditTrailState(
                logPath: StardewInstall.auditLogURL(forModSetDirectory: modSetDirectory).path,
                recentEntries: [],
                lastErrorMessage: nil
            ),
            dataStoreIssues: smartModSetLoad.issue.map { [$0] } ?? [],
            pendingSourceCleanupOffer: nil
        )
    }

    private func loadUserSmartModSets() -> (
        smartModSets: [UserSmartModSet],
        issue: DataStoreIssue?
    ) {
        do {
            let smartModSets = try UserSmartModSetStore.loadSmartModSets(
                from: smartModSetStoreURL
            )
            canSaveUserSmartModSets.withLock { $0 = true }
            return (smartModSets, nil)
        } catch {
            do {
                let recoveryURL = try UserSmartModSetStore.preserveUnreadableStore(
                    at: smartModSetStoreURL
                )
                canSaveUserSmartModSets.withLock { $0 = true }
                let detail = AppStrings.Status.savedSearchesPreserved(
                    recoveryURL.lastPathComponent
                )
                AppLog.smartModSets.error("\(detail, privacy: .private)")
                return (
                    [],
                    DataStoreIssue(
                        id: "user-smart-mod-sets",
                        title: AppStrings.Spotlight.smartModSetDescription,
                        detail: detail
                    )
                )
            } catch let recoveryError {
                canSaveUserSmartModSets.withLock { $0 = false }
                let detail = AppStrings.Status.couldNotPreserveSavedSearches(
                    recoveryError.localizedDescription
                )
                AppLog.smartModSets.error("\(detail, privacy: .private)")
                return (
                    [],
                    DataStoreIssue(
                        id: "user-smart-mod-sets",
                        title: AppStrings.Spotlight.smartModSetDescription,
                        detail: detail
                    )
                )
            }
        }
    }

    func stateByRestoringSavedFolder(from currentState: ModManagerState) -> ModManagerState {
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
