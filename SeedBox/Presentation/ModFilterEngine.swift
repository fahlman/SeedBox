import Foundation

struct ModFilterContext {
    var state: ModManagerState
    var dependencyGraph: ModDependencyGraph
}

enum ModFilterEngine {
    static func filteredMods(
        in state: ModManagerState,
        librarySelection: ModLibrarySelection,
        searchText: String,
        dependencyGraph: ModDependencyGraph
    ) -> [ModInfo] {
        let context = ModFilterContext(state: state, dependencyGraph: dependencyGraph)
        let query = ModSearchQuery(searchText)

        return state.mods.filter { mod in
            includes(mod, in: librarySelection, context: context)
                && query.matches(
                    mod,
                    in: dependencyGraph,
                    hasAvailableUpdate: state.availableUpdate(for: mod) != nil
                )
        }
    }

    static func count(for smartSet: SmartModSet, in state: ModManagerState) -> Int {
        switch smartSet {
        case .recentlyDeleted:
            return recentlyDeletedArchivedMods(in: state).count
        default:
            let context = ModFilterContext(
                state: state,
                dependencyGraph: ModDependencyGraph(mods: state.mods)
            )
            return state.mods.filter { mod in
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
            guard let smartModSet = context.state.userSmartModSets.first(where: { $0.id == id }) else {
                return false
            }
            return savedSearch(smartModSet.searchText, matches: mod, context: context)
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
        case .smapiMods:
            return !mod.isContentPatcherContentPack
        case .contentPatcherMods:
            return mod.isContentPatcherContentPack
        case .updatesAvailable:
            return context.state.availableUpdate(for: mod) != nil
        case .errors:
            return errorModIDs(in: context.state).contains(mod.id)
        case .warnings:
            return warningModIDs(in: context.state).contains(mod.id)
        case .recentlyAdded:
            return recentModIDs(for: [.modsAdded], in: context.state).contains(mod.id)
        case .recentlyUpdated:
            return recentlyUpdatedModIDs(in: context.state).contains(mod.id)
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

    static func count(for smartModSet: UserSmartModSet, in state: ModManagerState) -> Int {
        let context = ModFilterContext(
            state: state,
            dependencyGraph: ModDependencyGraph(mods: state.mods)
        )
        return state.mods.filter { mod in
            savedSearch(smartModSet.searchText, matches: mod, context: context)
        }.count
    }

    private static func savedSearch(
        _ searchText: String,
        matches mod: ModInfo,
        context: ModFilterContext
    ) -> Bool {
        ModSearchQuery(searchText).matches(
            mod,
            in: context.dependencyGraph,
            hasAvailableUpdate: context.state.availableUpdate(for: mod) != nil
        )
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

extension ModInfo {
    var isContentPatcherContentPack: Bool {
        manifest?.contentPackFor?.uniqueID?.caseInsensitiveCompare("Pathoschild.ContentPatcher") == .orderedSame
    }
}
