import Foundation

struct ModManagerPreferences {
    private let defaults: UserDefaults

    private enum Key {
        static let lastAppliedModSetID = "lastAppliedModSetID"
        static let lastKnownModFolderTokens = "lastKnownModFolderTokens"
        static let modsDirectoryPath = "modsDirectoryPath"
        static let moveModFilesToTrashAfterAddingMods = "moveModFilesToTrashAfterAddingMods"
        static let suppressAddModsSuccessNotification = "suppressAddModsSuccessNotification"
        static let automaticallyPrunesExpiredArchives = "automaticallyPrunesExpiredArchives"
        static let archiveRetentionDays = "archiveRetentionDays"
        static let checksForModUpdates = "checksForModUpdates"
        static let bisectionSession = "bisectionSession"
        static let announcedLogSessionDate = "announcedLogSessionDate"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var modsDirectoryPath: String? {
        defaults.string(forKey: Key.modsDirectoryPath)
    }

    var hasLastKnownModFolderTokens: Bool {
        defaults.object(forKey: Key.lastKnownModFolderTokens) != nil
    }

    var lastKnownModFolderTokens: Set<String> {
        Set(defaults.stringArray(forKey: Key.lastKnownModFolderTokens) ?? [])
    }

    var lastAppliedModSetID: String? {
        defaults.string(forKey: Key.lastAppliedModSetID)
    }

    var sourceCleanupSettings: SourceCleanupSettings {
        SourceCleanupSettings(
            moveModFilesToTrashAfterAddingMods: moveModFilesToTrashAfterAddingMods,
            suppressAddModsSuccessNotification: suppressAddModsSuccessNotification
        )
    }

    var archiveSettings: ArchiveSettings {
        ArchiveSettings(
            automaticallyPrunesExpiredArchives: automaticallyPrunesExpiredArchives,
            retentionDays: archiveRetentionDays
        )
    }

    var moveModFilesToTrashAfterAddingMods: Bool {
        get {
            defaults.bool(forKey: Key.moveModFilesToTrashAfterAddingMods)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.moveModFilesToTrashAfterAddingMods)
        }
    }

    var suppressAddModsSuccessNotification: Bool {
        get {
            defaults.bool(forKey: Key.suppressAddModsSuccessNotification)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.suppressAddModsSuccessNotification)
        }
    }

    var automaticallyPrunesExpiredArchives: Bool {
        get {
            if defaults.object(forKey: Key.automaticallyPrunesExpiredArchives) == nil {
                return true
            }
            return defaults.bool(forKey: Key.automaticallyPrunesExpiredArchives)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.automaticallyPrunesExpiredArchives)
        }
    }

    /// Off by default: checking sends mod metadata over the network, so the
    /// user opts in explicitly.
    var checksForModUpdates: Bool {
        get {
            defaults.bool(forKey: Key.checksForModUpdates)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.checksForModUpdates)
        }
    }

    /// The log session that was already announced at launch, so the same
    /// session is never announced twice.
    var announcedLogSessionDate: Date? {
        get {
            guard defaults.object(forKey: Key.announcedLogSessionDate) != nil else {
                return nil
            }
            return Date(timeIntervalSince1970: defaults.double(forKey: Key.announcedLogSessionDate))
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: Key.announcedLogSessionDate)
            } else {
                defaults.removeObject(forKey: Key.announcedLogSessionDate)
            }
        }
    }

    var archiveRetentionDays: Int {
        get {
            let storedValue = defaults.integer(forKey: Key.archiveRetentionDays)
            guard storedValue > 0 else {
                return ArchiveSettings.defaultRetentionDays
            }
            return storedValue
        }
        nonmutating set {
            defaults.set(max(1, newValue), forKey: Key.archiveRetentionDays)
        }
    }

    /// The problem-mod search survives quitting Seed Box while the game runs.
    var bisectionSession: ModBisectionSession? {
        get {
            guard let data = defaults.data(forKey: Key.bisectionSession) else {
                return nil
            }

            return try? JSONDecoder().decode(ModBisectionSession.self, from: data)
        }
        nonmutating set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue)
            else {
                defaults.removeObject(forKey: Key.bisectionSession)
                return
            }

            defaults.set(data, forKey: Key.bisectionSession)
        }
    }

    func save(_ state: ModManagerState) {
        defaults.set(state.modsDirectoryPath, forKey: Key.modsDirectoryPath)
        bisectionSession = state.bisectionSession

        guard state.hasLoadedMods else {
            return
        }

        defaults.set(
            Self.modFolderTokens(from: state.mods),
            forKey: Key.lastKnownModFolderTokens
        )

        if let appliedModSetID = state.appliedModSetID {
            defaults.set(appliedModSetID, forKey: Key.lastAppliedModSetID)
        } else {
            defaults.removeObject(forKey: Key.lastAppliedModSetID)
        }
    }

    private static func modFolderTokens(from mods: [ModInfo]) -> [String] {
        Set(mods.map { $0.enabledFolderName.normalizedFolderToken })
            .sorted()
    }
}

struct SourceCleanupSettings: Equatable, Sendable {
    var moveModFilesToTrashAfterAddingMods: Bool
    var suppressAddModsSuccessNotification: Bool
}

struct ArchiveSettings: Equatable, Sendable {
    static let defaultRetentionDays = 30

    var automaticallyPrunesExpiredArchives: Bool
    var retentionDays: Int

    var normalizedRetentionDays: Int {
        max(1, retentionDays)
    }

    var retentionInterval: TimeInterval {
        TimeInterval(normalizedRetentionDays) * 24 * 60 * 60
    }
}
