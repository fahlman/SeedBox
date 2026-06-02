import Foundation

struct ModManagerPreferences {
    private let defaults: UserDefaults

    private enum Key {
        static let modsDirectoryPath = "modsDirectoryPath"
        static let selectedModSetID = "selectedModSetID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var modsDirectoryPath: String? {
        defaults.string(forKey: Key.modsDirectoryPath)
    }

    var selectedModSetID: String {
        defaults.string(forKey: Key.selectedModSetID) ?? ModSetStore.defaultSetID
    }

    func save(_ state: ModManagerState) {
        defaults.set(state.modsDirectoryPath, forKey: Key.modsDirectoryPath)
        defaults.set(state.selectedModSetID, forKey: Key.selectedModSetID)
    }
}
