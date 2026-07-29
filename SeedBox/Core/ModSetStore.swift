import Foundation

enum ModSetStoreError: Error, Equatable, LocalizedError, Sendable {
    case duplicateSetName(String)
    case missingSet(String)
    case invalidSetID(String)
    case storedSetIDMismatch(fileID: String, storedID: String)

    var errorDescription: String? {
        switch self {
        case .duplicateSetName(let name):
            return AppStrings.Errors.duplicateModSetName(name)
        case .missingSet(let id):
            return AppStrings.Errors.modSetNotFound(id)
        case .invalidSetID(let id):
            return CocoaError(
                .fileReadInvalidFileName,
                userInfo: [NSFilePathErrorKey: id]
            ).localizedDescription
        case .storedSetIDMismatch:
            return CocoaError(.fileReadCorruptFile).localizedDescription
        }
    }
}

struct ModSetLoadResult: Equatable, Sendable {
    var sets: [ModSet]
    var issues: [ModSetLoadIssue]
}

struct ModSetLoadIssue: Error, Equatable, LocalizedError, Sendable {
    var fileName: String
    var reason: String

    var errorDescription: String? {
        "\(fileName): \(reason)"
    }
}

enum ModSetStore {
    static let allSetID = "all"
    static let allSetName = AppStrings.ModSetNames.all
    static let defaultSetID = "default"
    static let defaultSetName = AppStrings.ModSetNames.defaultSet
    static let noneSetID = "none"
    static let noneSetName = AppStrings.ModSetNames.none

    private static let appProvidedSetIDs: Set<String> = [
        allSetID,
        defaultSetID,
        noneSetID
    ]

    static func loadSets(
        install: StardewInstall,
        currentMods: [ModInfo],
        fileManager: FileManager = .default
    ) throws -> [ModSet] {
        let result = try loadSetsWithIssues(
            install: install,
            currentMods: currentMods,
            fileManager: fileManager
        )
        if let issue = result.issues.first {
            throw issue
        }
        return result.sets
    }

    static func loadSetsWithIssues(
        install: StardewInstall,
        currentMods: [ModInfo],
        fileManager: FileManager = .default
    ) throws -> ModSetLoadResult {
        try createStoreDirectoryIfNeeded(install: install, fileManager: fileManager)

        let existingSetURLs = try setFileURLs(install: install, fileManager: fileManager)
        var result = loadUserSets(
            from: existingSetURLs,
            currentMods: currentMods,
            install: install,
            fileManager: fileManager
        )
        if result.sets.isEmpty {
            result.sets = starterSets(from: currentMods)
            for set in result.sets {
                try saveSet(set, install: install, fileManager: fileManager)
            }
        }

        result.sets.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return result
    }

    static func createSet(
        named name: String,
        from sourceSet: ModSet,
        existingSets: [ModSet],
        parentID: String? = nil
    ) throws -> ModSet {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return ModSet(
                id: UUID().uuidString,
                name: AppStrings.ModSetNames.untitledSet,
                disabledFolderNames: normalizeFolderNames(sourceSet.disabledFolderNames),
                parentID: parentID
            )
        }

        let normalizedName = trimmedName.lowercased()
        let nameAlreadyExists = existingSets.contains { set in
            set.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
        }
        if nameAlreadyExists {
            throw ModSetStoreError.duplicateSetName(trimmedName)
        }

        return ModSet(
            id: UUID().uuidString,
            name: trimmedName,
            disabledFolderNames: normalizeFolderNames(sourceSet.disabledFolderNames),
            parentID: parentID
        )
    }

    static func saveSet(
        _ set: ModSet,
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws {
        let identifier = try validatedIdentifier(set.id)
        try createStoreDirectoryIfNeeded(install: install, fileManager: fileManager)
        let storedSet = StoredModSet(
            id: set.id,
            name: set.name,
            disabledFolderNames: normalizeFolderNames(set.disabledFolderNames),
            isEditable: set.isEditable,
            parentID: set.parentID,
            enabledFolderNames: set.enabledFolderNames.isEmpty
                ? nil
                : normalizeFolderNames(set.enabledFolderNames)
        )
        try saveStoredSet(
            storedSet,
            to: identifier.fileURL(in: install.modSetDirectoryURL),
            fileManager: fileManager
        )
    }

    static func deleteSet(
        _ set: ModSet,
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws {
        let identifier = try validatedIdentifier(set.id)
        let url = identifier.fileURL(in: install.modSetDirectoryURL)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ModSetStoreError.missingSet(set.id)
        }

        try fileManager.removeItem(at: url)
    }

    @discardableResult
    static func applySet(
        _ set: ModSet,
        in allSets: [ModSet] = [],
        install: StardewInstall,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) throws -> Int {
        let mods = try ModLibrary.scan(install: install, fileManager: fileManager)
        // Resolve the full inheritance chain before touching files so the Mods
        // folder reflects the fully resolved state, not just this set's own
        // choices. Passing the set in isolation falls back to its own choices.
        let resolvedSet = ModSetResolver.resolve(set, in: allSets)

        let changes = try ModLibrary.applyEnabledStates(
            to: mods,
            install: install,
            fileManager: fileManager,
            moveItem: moveItem,
            shouldEnable: resolvedSet.isEnabled
        )
        return changes.count
    }

    static func snapshotSet(
        id: String,
        name: String,
        from mods: [ModInfo],
        isEditable: Bool = true
    ) -> ModSet {
        ModSet(
            id: id,
            name: name,
            disabledFolderNames: normalizeFolderNames(
                mods.filter { !$0.isEnabled }.map(\.enabledFolderName)
            ),
            isEditable: isEditable
        )
    }

    private struct StoredModSet: Codable {
        var id: String
        var name: String
        var disabledFolderNames: [String]
        var isEditable: Bool?
        var parentID: String?
        var enabledFolderNames: [String]?
    }

    private static func setFileURLs(
        install: StardewInstall,
        fileManager: FileManager
    ) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: install.modSetDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "plist" }
    }

    private static func loadUserSets(
        from urls: [URL],
        currentMods: [ModInfo],
        install: StardewInstall,
        fileManager: FileManager
    ) -> ModSetLoadResult {
        var sets: [ModSet] = []
        var issues: [ModSetLoadIssue] = []
        for url in urls {
            do {
                let fileIdentifier = try ModSetIdentifier(fileURL: url)
                let stored = try loadStoredSet(at: url)
                let storedIdentifier = try validatedIdentifier(stored.id)
                guard storedIdentifier == fileIdentifier else {
                    throw ModSetStoreError.storedSetIDMismatch(
                        fileID: fileIdentifier.rawValue,
                        storedID: storedIdentifier.rawValue
                    )
                }

                let isEditable = stored.isEditable ?? defaultEditability(for: stored.id)
                var set = ModSet(
                    id: stored.id,
                    name: stored.name,
                    disabledFolderNames: normalizeFolderNames(stored.disabledFolderNames),
                    isEditable: isEditable,
                    parentID: stored.parentID,
                    enabledFolderNames: normalizeFolderNames(stored.enabledFolderNames ?? [])
                )
                set = appProvidedSet(for: set.id, currentMods: currentMods) ?? set

                if stored.isEditable == nil
                    || stored.isEditable != set.isEditable
                    || set.name != stored.name
                    || set.disabledFolderNames != stored.disabledFolderNames
                    || set.parentID != stored.parentID
                    || set.enabledFolderNames != normalizeFolderNames(stored.enabledFolderNames ?? []) {
                    try saveSet(set, install: install, fileManager: fileManager)
                }
                sets.append(set)
            } catch {
                issues.append(
                    ModSetLoadIssue(
                        fileName: url.lastPathComponent,
                        reason: error.localizedDescription
                    )
                )
                continue
            }
        }
        return ModSetLoadResult(sets: sets, issues: issues)
    }

    private static func starterSets(from mods: [ModInfo]) -> [ModSet] {
        [
            allStarterSet(),
            defaultStarterSet(from: mods),
            noneStarterSet(from: mods)
        ]
    }

    private static func allStarterSet() -> ModSet {
        ModSet(
            id: allSetID,
            name: allSetName,
            disabledFolderNames: [],
            isEditable: false
        )
    }

    private static func defaultStarterSet(from mods: [ModInfo]) -> ModSet {
        ModSet(
            id: defaultSetID,
            name: defaultSetName,
            disabledFolderNames: normalizeFolderNames(
                mods
                    .filter { !SMAPIIdentifiers.isBundledMod($0) }
                    .map(\.enabledFolderName)
            ),
            isEditable: false
        )
    }

    private static func noneStarterSet(from mods: [ModInfo]) -> ModSet {
        ModSet(
            id: noneSetID,
            name: noneSetName,
            disabledFolderNames: normalizeFolderNames(mods.map(\.enabledFolderName)),
            isEditable: false
        )
    }

    private static func createStoreDirectoryIfNeeded(
        install: StardewInstall,
        fileManager: FileManager
    ) throws {
        guard fileManager.directoryExists(at: install.modSetDirectoryURL) else {
            try fileManager.createDirectory(
                at: install.modSetDirectoryURL,
                withIntermediateDirectories: true
            )
            return
        }
    }

    private static func loadStoredSet(at url: URL) throws -> StoredModSet {
        let data = try Data(contentsOf: url)
        return try PropertyListDecoder().decode(StoredModSet.self, from: data)
    }

    private static func saveStoredSet(
        _ storedSet: StoredModSet,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(storedSet)
        try data.write(to: url, options: .atomic)
    }

    private static func validatedIdentifier(_ setID: String) throws -> ModSetIdentifier {
        do {
            return try ModSetIdentifier(setID)
        } catch {
            throw ModSetStoreError.invalidSetID(setID)
        }
    }

    private static func defaultEditability(for setID: String) -> Bool {
        !appProvidedSetIDs.contains(setID)
    }

    private static func appProvidedSet(for setID: String, currentMods: [ModInfo]) -> ModSet? {
        switch setID {
        case allSetID:
            return allStarterSet()
        case defaultSetID:
            return defaultStarterSet(from: currentMods)
        case noneSetID:
            return noneStarterSet(from: currentMods)
        default:
            return nil
        }
    }

    private static func normalizeFolderNames(_ folderNames: [String]) -> [String] {
        var seenTokens: Set<String> = []
        var normalizedFolderNames: [String] = []

        for folderName in folderNames {
            guard let trimmed = folderName.trimmedNonEmpty else {
                continue
            }

            let canonicalName = trimmed.trimmingPrefix(Character("."))
            let token = canonicalName.normalizedFolderToken
            guard !token.isEmpty else {
                continue
            }
            guard !seenTokens.contains(token) else {
                continue
            }

            seenTokens.insert(token)
            normalizedFolderNames.append(canonicalName)
        }

        return normalizedFolderNames.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
