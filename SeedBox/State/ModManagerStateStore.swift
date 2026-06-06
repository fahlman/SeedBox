import Foundation

struct ModManagerStateStore {
    private let folderAccess: SecurityScopedFolderAccess
    private let modSetDirectory: URL
    private let preferences: ModManagerPreferences

    init(
        folderAccess: SecurityScopedFolderAccess,
        modSetDirectory: URL,
        preferences: ModManagerPreferences
    ) {
        self.folderAccess = folderAccess
        self.modSetDirectory = modSetDirectory
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
        nonmutating set {
            preferences.moveModFilesToTrashAfterAddingMods = newValue
        }
    }

    var suppressAddModsSuccessNotification: Bool {
        get {
            preferences.suppressAddModsSuccessNotification
        }
        nonmutating set {
            preferences.suppressAddModsSuccessNotification = newValue
        }
    }

    var automaticallyPrunesExpiredArchives: Bool {
        get {
            preferences.automaticallyPrunesExpiredArchives
        }
        nonmutating set {
            preferences.automaticallyPrunesExpiredArchives = newValue
        }
    }

    var archiveRetentionDays: Int {
        get {
            preferences.archiveRetentionDays
        }
        nonmutating set {
            preferences.archiveRetentionDays = newValue
        }
    }

    func save(_ state: ModManagerState) {
        preferences.save(state)
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
