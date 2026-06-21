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

struct ModLibraryItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case builtInSmartModSet
        case userSmartModSet
        case modSet
    }

    var selection: ModLibrarySelection
    var title: String
    var systemImage: String
    var count: Int
    var kind: Kind
    var isUserEditable: Bool

    var id: String {
        selection.id
    }
}

enum ModLibrarySelection: Hashable, Sendable {
    case builtInSmart(SmartModSet)
    case userSmart(String)
    case modSet(String)

    static let smartPrefix = "smart:"
    static let userSmartPrefix = "userSmart:"
    static let modSetPrefix = "modSet:"
    static let initialID = modSetID(ModSetStore.initialSetID)

    init(id: String) {
        if id.hasPrefix(Self.smartPrefix) {
            let rawValue = String(id.dropFirst(Self.smartPrefix.count))
            if rawValue == "problems" {
                self = .builtInSmart(.errors)
            } else {
                self = SmartModSet(rawValue: rawValue).map(Self.builtInSmart) ?? .builtInSmart(.allMods)
            }
        } else if id.hasPrefix(Self.userSmartPrefix) {
            self = .userSmart(String(id.dropFirst(Self.userSmartPrefix.count)))
        } else if id.hasPrefix(Self.modSetPrefix) {
            self = .modSet(String(id.dropFirst(Self.modSetPrefix.count)))
        } else if id.isEmpty {
            self = .modSet(ModSetStore.initialSetID)
        } else {
            self = .modSet(id)
        }
    }

    var id: String {
        switch self {
        case .builtInSmart(let smartSet):
            return Self.smartID(smartSet)
        case .userSmart(let id):
            return Self.userSmartID(id)
        case .modSet(let id):
            return Self.modSetID(id)
        }
    }

    var selectedModSetID: String? {
        switch self {
        case .builtInSmart, .userSmart:
            return nil
        case .modSet(let id):
            return id
        }
    }

    var smartSet: SmartModSet? {
        switch self {
        case .builtInSmart(let smartSet):
            return smartSet
        case .userSmart, .modSet:
            return nil
        }
    }

    var userSmartModSetID: String? {
        switch self {
        case .userSmart(let id):
            return id
        case .builtInSmart, .modSet:
            return nil
        }
    }

    var isSmartModSet: Bool {
        smartSet != nil || userSmartModSetID != nil
    }

    func systemImage(in state: ModManagerState) -> String {
        switch self {
        case .builtInSmart(let smartSet):
            return smartSet.systemImage
        case .userSmart(let id):
            return userSmartModSet(withID: id, in: state)?.systemImageName
                ?? UserSmartModSet.defaultSystemImageName
        case .modSet:
            return "folder"
        }
    }

    static func smartID(_ smartSet: SmartModSet) -> String {
        "\(smartPrefix)\(smartSet.rawValue)"
    }

    static func userSmartID(_ id: String) -> String {
        "\(userSmartPrefix)\(id)"
    }

    static func modSetID(_ id: String) -> String {
        "\(modSetPrefix)\(id)"
    }

    static func resolvedID(_ id: String, in state: ModManagerState) -> String {
        let selection = ModLibrarySelection(id: id)
        switch selection {
        case .builtInSmart:
            return selection.id
        case .userSmart(let id):
            if state.userSmartModSets.contains(where: { $0.id == id }) {
                return selection.id
            }
            return fallbackModSetID(in: state)
        case .modSet(let id):
            let availableIDs = Set(state.modSets.map(\.id))
            if availableIDs.contains(id) {
                return selection.id
            }
            return fallbackModSetID(in: state)
        }
    }

    func title(in state: ModManagerState) -> String {
        switch self {
        case .builtInSmart(let smartSet):
            return smartSet.title
        case .userSmart(let id):
            return userSmartModSet(withID: id, in: state)?.name ?? AppStrings.App.name
        case .modSet(let id):
            return state.modSets.first { $0.id == id }?.name ?? AppStrings.App.name
        }
    }

    func item(in state: ModManagerState) -> ModLibraryItem? {
        switch self {
        case .builtInSmart(let smartSet):
            return ModLibraryItem(
                selection: self,
                title: smartSet.title,
                systemImage: smartSet.systemImage,
                count: ModFilterEngine.count(for: smartSet, in: state),
                kind: .builtInSmartModSet,
                isUserEditable: false
            )
        case .userSmart(let id):
            guard let smartModSet = userSmartModSet(withID: id, in: state) else {
                return nil
            }
            return ModLibraryItem(
                selection: self,
                title: smartModSet.name,
                systemImage: smartModSet.systemImageName,
                count: ModFilterEngine.count(for: smartModSet, in: state),
                kind: .userSmartModSet,
                isUserEditable: true
            )
        case .modSet(let id):
            guard let modSet = state.modSets.first(where: { $0.id == id }) else {
                return nil
            }
            return ModLibraryItem(
                selection: self,
                title: modSet.name,
                systemImage: modSet.isUserEditable ? "folder" : "folder.badge.gearshape",
                count: Self.modCount(for: modSet, in: state),
                kind: .modSet,
                isUserEditable: modSet.isUserEditable
            )
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

    static func builtInSmartItems(in state: ModManagerState) -> [ModLibraryItem] {
        SmartModSet.allCases.compactMap { smartSet in
            ModLibrarySelection.builtInSmart(smartSet).item(in: state)
        }
    }

    static func userSmartItems(in state: ModManagerState) -> [ModLibraryItem] {
        state.userSmartModSets.compactMap { smartModSet in
            ModLibrarySelection.userSmart(smartModSet.id).item(in: state)
        }
    }

    static func modSetItems(in state: ModManagerState) -> [ModLibraryItem] {
        state.modSets.compactMap { modSet in
            ModLibrarySelection.modSet(modSet.id).item(in: state)
        }
    }

    private static func fallbackModSetID(in state: ModManagerState) -> String {
        let availableIDs = Set(state.modSets.map(\.id))
        if availableIDs.contains(state.selectedModSetID) {
            return modSetID(state.selectedModSetID)
        }
        if let firstUserSetID = state.modSets.first(where: { !$0.isIncluded })?.id {
            return modSetID(firstUserSetID)
        }
        if availableIDs.contains(ModSetStore.defaultSetID) {
            return modSetID(ModSetStore.defaultSetID)
        }
        if let firstSetID = state.modSets.first?.id {
            return modSetID(firstSetID)
        }
        return initialID
    }

    private static func modCount(for set: ModSet, in state: ModManagerState) -> Int {
        let resolvedSet = ModSetResolver.resolve(set)
        return state.mods.filter { mod in
            resolvedSet.isEnabled(mod)
        }.count
    }

    private func userSmartModSet(withID id: String, in state: ModManagerState) -> UserSmartModSet? {
        state.userSmartModSets.first { $0.id == id }
    }
}
