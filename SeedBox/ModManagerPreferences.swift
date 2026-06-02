import Foundation

struct ModManagerPreferences {
    private let defaults: UserDefaults

    private enum Key {
        static let lastAppliedModSetID = "lastAppliedModSetID"
        static let lastKnownModFolderTokens = "lastKnownModFolderTokens"
        static let modsDirectoryPath = "modsDirectoryPath"
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

    func save(_ state: ModManagerState) {
        defaults.set(state.modsDirectoryPath, forKey: Key.modsDirectoryPath)

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
