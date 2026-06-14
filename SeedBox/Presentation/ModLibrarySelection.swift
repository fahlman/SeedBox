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
        switch self {
        case .recentlyDeleted:
            return ModLibrarySelection.recentlyDeletedArchivedMods(in: state).count
        default:
            return state.mods.filter { mod in
                includes(mod, in: state)
            }.count
        }
    }

    func includes(_ mod: ModInfo, in state: ModManagerState) -> Bool {
        switch self {
        case .allMods:
            return true
        case .smapiMods:
            return !mod.isContentPatcherContentPack
        case .contentPatcherMods:
            return mod.isContentPatcherContentPack
        case .updatesAvailable:
            return state.availableUpdate(for: mod) != nil
        case .errors:
            return Self.errorModIDs(in: state).contains(mod.id)
        case .warnings:
            return Self.warningModIDs(in: state).contains(mod.id)
        case .recentlyAdded:
            return Self.recentModIDs(for: [.modsAdded], in: state).contains(mod.id)
        case .recentlyUpdated:
            return Self.recentlyUpdatedModIDs(in: state).contains(mod.id)
        case .recentlyDeleted:
            return false
        }
    }

    private static func errorModIDs(in state: ModManagerState) -> Set<String> {
        var ids = Set(
            state.mods
                .filter(\.hasMissingRequiredDependencies)
                .map(\.id)
        )
        ids.formUnion(state.smapiVersionIssues.map(\.id))
        ids.formUnion(state.lastSessionIssues.map(\.mod.id))
        for duplicateGroup in state.duplicateGroups {
            ids.formUnion(duplicateGroup.mods.map(\.id))
        }
        return ids
    }

    private static func warningModIDs(in state: ModManagerState) -> Set<String> {
        let errorIDs = errorModIDs(in: state)
        return Set(
            state.mods
                .filter { mod in
                    mod.hasMissingOptionalDependencies && !errorIDs.contains(mod.id)
                }
                .map(\.id)
        )
    }

    private static func recentlyUpdatedModIDs(in state: ModManagerState) -> Set<String> {
        var ids = recentModIDs(for: [.modsUpdated], in: state)
        let archivedUpdatedMods = state.archivedMods.filter { archivedMod in
            archivedMod.reason == .updated
        }
        for archivedMod in archivedUpdatedMods {
            if let currentMod = ModArchive.currentMod(for: archivedMod, in: state.mods) {
                ids.insert(currentMod.id)
            }
        }
        return ids
    }

    private static func recentModIDs(
        for actions: Set<AuditLogAction>,
        in state: ModManagerState
    ) -> Set<String> {
        var ids = Set<String>()
        let modsByID = Dictionary(uniqueKeysWithValues: state.mods.map { ($0.id, $0) })
        let modsByPath = Dictionary(uniqueKeysWithValues: state.mods.map { ($0.url.standardizedFileURL.path, $0) })
        let modsByFolderToken = Dictionary(grouping: state.mods) { mod in
            mod.enabledFolderName.normalizedFolderToken
        }
        let modsByDisplayName = Dictionary(grouping: state.mods, by: { $0.displayName.lowercased() })

        for entry in state.auditTrail.recentEntries.reversed() where actions.contains(entry.action) {
            for subject in entry.subjects where subject.kind == .mod {
                if let id = subject.id, modsByID[id] != nil {
                    ids.insert(id)
                    continue
                }

                if let path = subject.path,
                   let mod = modsByPath[URL(fileURLWithPath: path).standardizedFileURL.path] {
                    ids.insert(mod.id)
                    continue
                }

                let folderToken = subject.name.normalizedFolderToken
                if let mod = modsByFolderToken[folderToken]?.first {
                    ids.insert(mod.id)
                    continue
                }

                if let mod = modsByDisplayName[subject.name.lowercased()]?.first {
                    ids.insert(mod.id)
                }
            }
        }

        return ids
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
        switch self {
        case .smart(let smartSet):
            return smartSet.includes(mod, in: state)
        case .modSet:
            return true
        }
    }

    static func recentlyDeletedArchivedMods(in state: ModManagerState) -> [ArchivedModInfo] {
        state.archivedMods
            .filter { archivedMod in
                archivedMod.reason == .deleted
            }
            .sorted { lhs, rhs in
                switch (lhs.archivedDate, rhs.archivedDate) {
                case let (lhsDate?, rhsDate?):
                    lhsDate > rhsDate
                case (.some, nil):
                    true
                case (nil, .some):
                    false
                case (nil, nil):
                    lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }
            }
    }
}

private extension ModInfo {
    var isContentPatcherContentPack: Bool {
        manifest?.contentPackFor?.uniqueID?.caseInsensitiveCompare("Pathoschild.ContentPatcher") == .orderedSame
    }
}
