import Foundation

struct ModDuplicateGroup: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var mods: [ModInfo]
}

struct ModSetDifference: Identifiable, Equatable, Sendable {
    enum Change: Equatable, Sendable {
        case enable
        case disable
    }

    var id: String { mod.id }
    var mod: ModInfo
    var change: Change
}

struct ModSetComparison: Identifiable, Equatable, Sendable {
    var id: String { modSet.id }
    var modSet: ModSet
    var differences: [ModSetDifference]

    var enableCount: Int {
        differences.filter { $0.change == .enable }.count
    }

    var disableCount: Int {
        differences.filter { $0.change == .disable }.count
    }

    var hasDifferences: Bool {
        !differences.isEmpty
    }
}

struct ModArchiveSummary: Equatable, Sendable {
    var archivedModCount: Int = 0
    var totalByteCount: Int64 = 0
    var oldestArchiveDate: Date?
    var newestArchiveDate: Date?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalByteCount, countStyle: .file)
    }
}

struct InvalidModFolder: Identifiable, Equatable, Sendable {
    var id: String { url.path }
    var url: URL
    var folderName: String
    var reason: String
}

struct ModLibraryScanResult: Equatable, Sendable {
    var mods: [ModInfo]
    var invalidFolders: [InvalidModFolder]
}

enum ModManagerInsights {
    static func duplicateGroups(in mods: [ModInfo]) -> [ModDuplicateGroup] {
        var groupsByKey: [String: [ModInfo]] = [:]
        var titlesByKey: [String: String] = [:]

        for mod in mods {
            let key: String
            let title: String
            if let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty {
                key = "id:\(uniqueID.normalizedDependencyID)"
                title = uniqueID
            } else {
                key = "folder:\(mod.enabledFolderName.normalizedFolderToken)"
                title = mod.enabledFolderName
            }

            groupsByKey[key, default: []].append(mod)
            titlesByKey[key] = title
        }

        return groupsByKey.compactMap { key, groupedMods in
            guard groupedMods.count > 1 else {
                return nil
            }

            let sortedMods = groupedMods.sorted {
                $0.folderName.localizedCaseInsensitiveCompare($1.folderName) == .orderedAscending
            }
            let title = sortedMods.first?.displayName ?? titlesByKey[key] ?? AppStrings.Mods.unknown

            return ModDuplicateGroup(
                id: key,
                title: title,
                detail: titlesByKey[key] ?? title,
                mods: sortedMods
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    static func comparison(for set: ModSet, currentMods: [ModInfo]) -> ModSetComparison {
        let differences = currentMods.compactMap { mod -> ModSetDifference? in
            let willBeEnabled = !set.disabledFolderTokens.contains(mod.enabledFolderName.normalizedFolderToken)
            guard mod.isEnabled != willBeEnabled else {
                return nil
            }

            return ModSetDifference(
                mod: mod,
                change: willBeEnabled ? .enable : .disable
            )
        }
        .sorted { lhs, rhs in
            lhs.mod.displayName.localizedCaseInsensitiveCompare(rhs.mod.displayName) == .orderedAscending
        }

        return ModSetComparison(modSet: set, differences: differences)
    }
}
