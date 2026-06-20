import Foundation

enum SmartModSet: String, CaseIterable, Identifiable, Sendable {
    case allMods
    case smapiMods
    case contentPatcherMods
    case updatesAvailable
    case errors
    case warnings
    case recentlyAdded
    case recentlyUpdated
    case recentlyDeleted

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .allMods:
            AppStrings.Library.allMods
        case .smapiMods:
            AppStrings.Library.smapiMods
        case .contentPatcherMods:
            AppStrings.Library.contentPatcherMods
        case .updatesAvailable:
            AppStrings.Library.updatesAvailable
        case .errors:
            AppStrings.Library.errors
        case .warnings:
            AppStrings.Library.warnings
        case .recentlyAdded:
            AppStrings.Library.recentlyAdded
        case .recentlyUpdated:
            AppStrings.Library.recentlyUpdated
        case .recentlyDeleted:
            AppStrings.Library.recentlyDeleted
        }
    }

    var systemImage: String {
        switch self {
        case .allMods:
            "shippingbox"
        case .smapiMods:
            "terminal"
        case .contentPatcherMods:
            "paintpalette"
        case .updatesAvailable:
            "arrow.up.circle"
        case .errors:
            "exclamationmark.octagon"
        case .warnings:
            "exclamationmark.triangle"
        case .recentlyAdded:
            "plus.circle"
        case .recentlyUpdated:
            "clock.arrow.circlepath"
        case .recentlyDeleted:
            "trash"
        }
    }

    func count(in state: ModManagerState) -> Int {
        ModFilterEngine.count(for: self, in: state)
    }

    func includes(_ mod: ModInfo, in state: ModManagerState) -> Bool {
        ModFilterEngine.includes(
            mod,
            in: self,
            context: ModFilterContext(
                state: state,
                dependencyGraph: ModDependencyGraph(mods: state.mods)
            )
        )
    }
}

enum ModLibrarySelection: Hashable, Sendable {
    case smart(SmartModSet)
    case modSet(String)

    static let smartPrefix = "smart:"
    static let modSetPrefix = "modSet:"
    static let defaultID = modSetID(ModSetStore.defaultSetID)

    init(id: String) {
        if id.hasPrefix(Self.smartPrefix) {
            let rawValue = String(id.dropFirst(Self.smartPrefix.count))
            if rawValue == "problems" {
                self = .smart(.errors)
            } else {
                self = SmartModSet(rawValue: rawValue).map(Self.smart) ?? .smart(.allMods)
            }
        } else if id.hasPrefix(Self.modSetPrefix) {
            self = .modSet(String(id.dropFirst(Self.modSetPrefix.count)))
        } else if id.isEmpty {
            self = .modSet(ModSetStore.defaultSetID)
        } else {
            self = .modSet(id)
        }
    }

    var id: String {
        switch self {
        case .smart(let smartSet):
            return Self.smartID(smartSet)
        case .modSet(let id):
            return Self.modSetID(id)
        }
    }

    var selectedModSetID: String? {
        switch self {
        case .smart:
            return nil
        case .modSet(let id):
            return id
        }
    }

    var smartSet: SmartModSet? {
        switch self {
        case .smart(let smartSet):
            return smartSet
        case .modSet:
            return nil
        }
    }

    var systemImage: String {
        switch self {
        case .smart(let smartSet):
            return smartSet.systemImage
        case .modSet:
            return "folder"
        }
    }

    static func smartID(_ smartSet: SmartModSet) -> String {
        "\(smartPrefix)\(smartSet.rawValue)"
    }

    static func modSetID(_ id: String) -> String {
        "\(modSetPrefix)\(id)"
    }

    static func resolvedID(_ id: String, in state: ModManagerState) -> String {
        let selection = ModLibrarySelection(id: id)
        switch selection {
        case .smart:
            return selection.id
        case .modSet(let id):
            let availableIDs = Set(state.modSets.map(\.id))
            if availableIDs.contains(id) {
                return selection.id
            }
            if availableIDs.contains(state.selectedModSetID) {
                return modSetID(state.selectedModSetID)
            }
            if let firstSetID = state.modSets.first?.id {
                return modSetID(firstSetID)
            }
            return defaultID
        }
    }

    func title(in state: ModManagerState) -> String {
        switch self {
        case .smart(let smartSet):
            return smartSet.title
        case .modSet(let id):
            return state.modSets.first { $0.id == id }?.name ?? AppStrings.App.name
        }
    }

    func includes(_ mod: ModInfo, in state: ModManagerState) -> Bool {
        ModFilterEngine.includes(
            mod,
            in: self,
            context: ModFilterContext(
                state: state,
                dependencyGraph: ModDependencyGraph(mods: state.mods)
            )
        )
    }

    static func recentlyDeletedArchivedMods(in state: ModManagerState) -> [ArchivedModInfo] {
        ModFilterEngine.recentlyDeletedArchivedMods(in: state)
    }
}
