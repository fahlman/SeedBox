import Foundation

struct ModFilterContext {
    var state: ModManagerState
    var dependencyGraph: ModDependencyGraph
    var availableUpdateModIDs: Set<ModInfo.ID>
    var errorModIDs: Set<ModInfo.ID>
    var warningModIDs: Set<ModInfo.ID>
    var recentlyAddedModIDs: Set<ModInfo.ID>
    var recentlyUpdatedModIDs: Set<ModInfo.ID>
    var userSearchQueries: [UserSmartModSet.ID: ModSearchQuery]

    init(state: ModManagerState, dependencyGraph: ModDependencyGraph) {
        self.state = state
        self.dependencyGraph = dependencyGraph

        availableUpdateModIDs = Set(
            state.mods.compactMap { mod in
                state.availableUpdate(for: mod) == nil ? nil : mod.id
            }
        )
        errorModIDs = ModFilterEngine.errorModIDs(in: state)
        warningModIDs = ModFilterEngine.warningModIDs(
            in: state,
            excluding: errorModIDs
        )
        recentlyAddedModIDs = ModFilterEngine.recentModIDs(
            for: [.modsAdded],
            in: state
        )
        recentlyUpdatedModIDs = ModFilterEngine.recentlyUpdatedModIDs(in: state)
        userSearchQueries = Dictionary(
            uniqueKeysWithValues: state.userSmartModSets.map {
                ($0.id, ModSearchQuery($0.searchText))
            }
        )
    }
}

enum ModFilterEngine {
    static func filteredMods(
        context: ModFilterContext,
        librarySelection: ModLibrarySelection,
        searchText: String
    ) -> [ModInfo] {
        let query = ModSearchQuery(searchText)

        return context.state.mods.filter { mod in
            includes(mod, in: librarySelection, context: context)
                && query.matches(
                    mod,
                    in: context.dependencyGraph,
                    hasAvailableUpdate: context.availableUpdateModIDs.contains(mod.id)
                )
        }
    }

    static func count(for smartSet: SmartModSet, context: ModFilterContext) -> Int {
        switch smartSet {
        case .recentlyDeleted:
            return recentlyDeletedArchivedMods(in: context.state).count
        default:
            return context.state.mods.filter { mod in
                includes(mod, in: smartSet, context: context)
            }.count
        }
    }

    static func includes(
        _ mod: ModInfo,
        in selection: ModLibrarySelection,
        context: ModFilterContext
    ) -> Bool {
        switch selection {
        case .builtInSmart(let smartSet):
            return includes(mod, in: smartSet, context: context)
        case .userSmart(let id):
            guard let query = context.userSearchQueries[id] else {
                return false
            }
            return savedSearch(query, matches: mod, context: context)
        case .modSet:
            return true
        }
    }

    static func includes(
        _ mod: ModInfo,
        in smartSet: SmartModSet,
        context: ModFilterContext
    ) -> Bool {
        switch smartSet {
        case .allMods:
            return true
        case .enabled:
            return mod.isEnabled
        case .disabled:
            return !mod.isEnabled
        case .smapiMods:
            return !mod.isContentPatcherContentPack
        case .contentPatcherMods:
            return mod.isContentPatcherContentPack
        case .updatesAvailable:
            return context.availableUpdateModIDs.contains(mod.id)
        case .errors:
            return context.errorModIDs.contains(mod.id)
        case .warnings:
            return context.warningModIDs.contains(mod.id)
        case .recentlyAdded:
            return context.recentlyAddedModIDs.contains(mod.id)
        case .recentlyUpdated:
            return context.recentlyUpdatedModIDs.contains(mod.id)
        case .recentlyDeleted:
            return false
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

    static func count(
        for smartModSet: UserSmartModSet,
        context: ModFilterContext
    ) -> Int {
        guard let query = context.userSearchQueries[smartModSet.id] else {
            return 0
        }
        return context.state.mods.filter { mod in
            savedSearch(query, matches: mod, context: context)
        }.count
    }

    private static func savedSearch(
        _ query: ModSearchQuery,
        matches mod: ModInfo,
        context: ModFilterContext
    ) -> Bool {
        query.matches(
            mod,
            in: context.dependencyGraph,
            hasAvailableUpdate: context.availableUpdateModIDs.contains(mod.id)
        )
    }

    fileprivate static func errorModIDs(in state: ModManagerState) -> Set<String> {
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

    fileprivate static func warningModIDs(
        in state: ModManagerState,
        excluding errorIDs: Set<String>
    ) -> Set<String> {
        return Set(
            state.mods
                .filter { mod in
                    mod.hasMissingOptionalDependencies && !errorIDs.contains(mod.id)
                }
                .map(\.id)
        )
    }

    fileprivate static func recentlyUpdatedModIDs(in state: ModManagerState) -> Set<String> {
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

    fileprivate static func recentModIDs(
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

extension ModInfo {
    var isContentPatcherContentPack: Bool {
        manifest?.contentPackFor?.uniqueID?.caseInsensitiveCompare("Pathoschild.ContentPatcher") == .orderedSame
    }
}
