import Foundation

public struct ModInfo: Identifiable, Equatable {
    public var id: String { url.path }

    public var folderName: String
    public var url: URL
    public var isEnabled: Bool
    public var manifest: ModManifest?
    public var missingRequiredDependencyIDs: [String] = []
    public var missingOptionalDependencyIDs: [String] = []

    public var displayName: String {
        manifest?.name ?? enabledFolderName
    }

    public var enabledFolderName: String {
        folderName.trimmingPrefix(Character("."))
    }

    public var versionText: String {
        manifest?.version ?? "Unknown version"
    }

    public var authorText: String {
        manifest?.author ?? "Unknown author"
    }

    public var stateText: String {
        isEnabled ? "Enabled" : "Disabled"
    }

    public var typeText: String {
        guard let manifest else {
            return "Unknown"
        }

        if manifest.contentPackFor?.uniqueID?.caseInsensitiveCompare("Pathoschild.ContentPatcher") == .orderedSame {
            return "Content Patcher"
        }

        return "SMAPI"
    }

    public var manifestMetadataText: String? {
        var segments: [String] = []

        if let contentPackFor = manifest?.contentPackFor?.uniqueID?.trimmedNonEmpty {
            segments.append("For \(contentPackFor)")
        }

        if let dependencies = manifest?.dependencies, !dependencies.isEmpty {
            let requiredCount = dependencies.filter { $0.isRequired != false }.count
            let optionalCount = dependencies.filter { $0.isRequired == false }.count

            if requiredCount > 0 && optionalCount > 0 {
                segments.append("\(requiredCount) required + \(optionalCount) optional deps")
            } else if requiredCount > 0 {
                segments.append("\(requiredCount) required \(requiredCount == 1 ? "dep" : "deps")")
            } else {
                segments.append("\(optionalCount) optional \(optionalCount == 1 ? "dep" : "deps")")
            }
        }

        guard !segments.isEmpty else {
            return nil
        }

        return segments.joined(separator: " • ")
    }

    public var hasMissingRequiredDependencies: Bool {
        !missingRequiredDependencyIDs.isEmpty
    }

    public var missingRequiredDependenciesText: String? {
        guard hasMissingRequiredDependencies else {
            return nil
        }
        return "Missing required: \(missingRequiredDependencyIDs.joined(separator: ", "))"
    }

    public var hasMissingOptionalDependencies: Bool {
        !missingOptionalDependencyIDs.isEmpty
    }

    public var missingOptionalDependenciesText: String? {
        guard hasMissingOptionalDependencies else {
            return nil
        }
        return "Missing optional: \(missingOptionalDependencyIDs.joined(separator: ", "))"
    }
}

public struct ModSearchQuery {
    private enum Field: String {
        case state
        case mod
        case author
        case type
    }

    private struct Term {
        var field: Field?
        var value: String
    }

    private var terms: [Term]

    public init(_ rawValue: String) {
        terms = Self.parse(rawValue)
    }

    public func matches(_ mod: ModInfo) -> Bool {
        guard !terms.isEmpty else {
            return true
        }

        return terms.allSatisfy { term in
            switch term.field {
            case .state:
                return mod.stateText.matchesSearchValue(term.value)
            case .mod:
                return "\(mod.displayName) \(mod.versionText)".matchesSearchValue(term.value)
            case .author:
                return mod.authorText.matchesSearchValue(term.value)
            case .type:
                return mod.typeText.matchesSearchValue(term.value)
            case nil:
                return [
                    mod.stateText,
                    mod.displayName,
                    mod.versionText,
                    mod.authorText,
                    mod.typeText,
                    mod.manifest?.description ?? "",
                    mod.manifest?.uniqueID ?? ""
                ].contains { $0.matchesSearchValue(term.value) }
            }
        }
    }

    private static func parse(_ rawValue: String) -> [Term] {
        tokens(in: rawValue).compactMap { token in
            guard let splitIndex = token.firstIndex(of: ":") else {
                return Term(field: nil, value: token)
            }

            let fieldName = String(token[..<splitIndex]).lowercased()
            let valueStartIndex = token.index(after: splitIndex)
            let value = String(token[valueStartIndex...])
            guard let field = Field(rawValue: fieldName), !value.isEmpty else {
                return Term(field: nil, value: token)
            }

            return Term(field: field, value: value)
        }
    }

    private static func tokens(in rawValue: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""
        var isInsideQuotes = false

        for character in rawValue {
            if character == "\"" {
                isInsideQuotes.toggle()
                continue
            }

            if character.isWhitespace && !isInsideQuotes {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                continue
            }

            currentToken.append(character)
        }

        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        return tokens
    }
}

public struct ModManifest: Codable, Equatable {
    public struct ContentPackFor: Codable, Equatable {
        public var uniqueID: String?

        private enum CodingKeys: String, CodingKey {
            case uniqueID = "UniqueID"
        }
    }

    public struct Dependency: Codable, Equatable {
        public var uniqueID: String?
        public var isRequired: Bool?

        private enum CodingKeys: String, CodingKey {
            case uniqueID = "UniqueID"
            case isRequired = "IsRequired"
        }
    }

    public var name: String?
    public var author: String?
    public var version: String?
    public var description: String?
    public var uniqueID: String?
    public var contentPackFor: ContentPackFor?
    public var dependencies: [Dependency]?

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case author = "Author"
        case version = "Version"
        case description = "Description"
        case uniqueID = "UniqueID"
        case contentPackFor = "ContentPackFor"
        case dependencies = "Dependencies"
    }
}

public struct ModSet: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var disabledFolderNames: [String]
    public var isDefault: Bool

    public init(
        id: String,
        name: String,
        disabledFolderNames: [String],
        isDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.disabledFolderNames = disabledFolderNames
        self.isDefault = isDefault
    }
}

public enum ModSetStoreError: Error, Equatable, LocalizedError {
    case cannotModifyDefaultSet
    case duplicateSetName(String)
    case missingSet(String)

    public var errorDescription: String? {
        switch self {
        case .cannotModifyDefaultSet:
            return "The default mod set cannot be edited."
        case .duplicateSetName(let name):
            return "A mod set named \(name) already exists."
        case .missingSet(let id):
            return "Mod set \(id) was not found."
        }
    }
}

public enum ModLibraryError: Error, Equatable, LocalizedError {
    case modFolderMissing(URL)
    case destinationExists(URL)
    case modAlreadyInstalled(String, URL)
    case invalidDisabledName(String)
    case noInstallableMods(URL)

    public var errorDescription: String? {
        switch self {
        case .modFolderMissing(let url):
            return "The mod folder does not exist at \(url.path)."
        case .destinationExists(let url):
            return "A mod already exists at \(url.path)."
        case .modAlreadyInstalled(let folderName, let url):
            return "\(folderName) is already installed at \(url.path)."
        case .invalidDisabledName(let name):
            return "The disabled folder name \(name) cannot be enabled safely."
        case .noInstallableMods(let url):
            return "No installable mod folders were found in \(url.path)."
        }
    }
}

public enum ModLibrary {
    public static func scan(
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> [ModInfo] {
        guard fileManager.directoryExists(at: install.modDirectoryURL) else {
            throw ModLibraryError.modFolderMissing(install.modDirectoryURL)
        }

        let folders = try fileManager.contentsOfDirectory(
            at: install.modDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        .filter { url in
            guard url.lastPathComponent != ".DS_Store" else {
                return false
            }
            return fileManager.directoryExists(at: url)
        }

        return folders
            .map { url in
                let manifestURL = findManifest(in: url, fileManager: fileManager)
                return ModInfo(
                    folderName: url.lastPathComponent,
                    url: url,
                    isEnabled: !url.lastPathComponent.hasPrefix("."),
                    manifest: manifestURL.flatMap { loadManifest(at: $0) }
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .withResolvedRequiredDependencies()
    }

    public static func setEnabled(
        _ mod: ModInfo,
        enabled: Bool,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard mod.isEnabled != enabled else {
            return mod.url
        }

        let destinationName: String
        if enabled {
            destinationName = mod.folderName.trimmingPrefix(Character("."))
            guard !destinationName.isEmpty else {
                throw ModLibraryError.invalidDisabledName(mod.folderName)
            }
        } else {
            destinationName = "." + mod.folderName.trimmingPrefix(Character("."))
        }

        let destinationURL = mod.url
            .deletingLastPathComponent()
            .appendingPathComponent(destinationName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw ModLibraryError.modAlreadyInstalled(mod.enabledFolderName, destinationURL)
        }

        try fileManager.moveItem(at: mod.url, to: destinationURL)
        return destinationURL
    }

    public static func installMods(
        from sourceURLs: [URL],
        into install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard fileManager.directoryExists(at: install.modDirectoryURL) else {
            throw ModLibraryError.modFolderMissing(install.modDirectoryURL)
        }

        var pendingInstalls: [(sourceURL: URL, destinationURL: URL)] = []
        var pendingDestinationURLsByToken: [String: URL] = [:]
        let existingModURLsByToken = installedModURLsByToken(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )

        for sourceURL in sourceURLs {
            let candidates = installCandidates(from: sourceURL, fileManager: fileManager)
            guard !candidates.isEmpty else {
                throw ModLibraryError.noInstallableMods(sourceURL)
            }

            for candidateURL in candidates {
                let folderName = candidateURL.lastPathComponent.trimmingPrefix(Character("."))
                guard !folderName.isEmpty else {
                    throw ModLibraryError.invalidDisabledName(candidateURL.lastPathComponent)
                }

                let destinationURL = install.modDirectoryURL
                    .appendingPathComponent(candidateURL.lastPathComponent)
                let destinationToken = folderName.normalizedFolderToken

                if fileManager.fileExists(atPath: destinationURL.path) {
                    throw ModLibraryError.destinationExists(destinationURL)
                }

                if let existingURL = existingModURLsByToken[destinationToken] {
                    throw ModLibraryError.modAlreadyInstalled(folderName, existingURL)
                }

                if let pendingDestinationURL = pendingDestinationURLsByToken[destinationToken] {
                    throw ModLibraryError.modAlreadyInstalled(folderName, pendingDestinationURL)
                }

                pendingDestinationURLsByToken[destinationToken] = destinationURL
                pendingInstalls.append((candidateURL, destinationURL))
            }
        }

        var installedURLs: [URL] = []
        do {
            for pendingInstall in pendingInstalls {
                try fileManager.copyItem(at: pendingInstall.sourceURL, to: pendingInstall.destinationURL)
                installedURLs.append(pendingInstall.destinationURL)
            }
        } catch {
            for installedURL in installedURLs.reversed() {
                try? fileManager.removeItem(at: installedURL)
            }
            throw error
        }

        return installedURLs
    }

    public static func trash(
        _ mod: ModInfo,
        fileManager: FileManager = .default
    ) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(
            at: mod.url,
            resultingItemURL: &resultingURL
        )
    }

    static func installCandidates(
        from sourceURL: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        if fileManager.fileExists(atPath: sourceURL.appendingPathComponent("manifest.json").path) {
            return [sourceURL]
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let modChildren = children.filter { childURL in
            fileManager.directoryExists(at: childURL)
                && findManifest(in: childURL, maximumDepth: 2, fileManager: fileManager) != nil
        }

        if !modChildren.isEmpty {
            return modChildren
        }

        if findManifest(in: sourceURL, maximumDepth: 2, fileManager: fileManager) != nil {
            return [sourceURL]
        }

        return []
    }

    private static func installedModURLsByToken(
        in modsDirectory: URL,
        fileManager: FileManager
    ) -> [String: URL] {
        let installedURLs = (try? fileManager.contentsOfDirectory(
            at: modsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []

        var urlsByToken: [String: URL] = [:]
        for installedURL in installedURLs where fileManager.directoryExists(at: installedURL) {
            let token = installedURL.lastPathComponent.normalizedFolderToken
            guard !token.isEmpty, urlsByToken[token] == nil else {
                continue
            }

            urlsByToken[token] = installedURL
        }

        return urlsByToken
    }

    private static func loadManifest(at url: URL) -> ModManifest? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(ModManifest.self, from: data)
    }

    private static func findManifest(
        in directoryURL: URL,
        maximumDepth: Int = 3,
        fileManager: FileManager = .default
    ) -> URL? {
        let directURL = directoryURL.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }

        guard maximumDepth > 0 else {
            return nil
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for childURL in children where fileManager.directoryExists(at: childURL) {
            if let foundURL = findManifest(
                in: childURL,
                maximumDepth: maximumDepth - 1,
                fileManager: fileManager
            ) {
                return foundURL
            }
        }

        return nil
    }
}

public enum ModSetStore {
    public static let defaultSetID = "default"
    public static let defaultSetName = "Default"

    public static func loadSets(
        install: StardewInstall,
        currentMods: [ModInfo],
        fileManager: FileManager = .default
    ) throws -> [ModSet] {
        try createStoreDirectoryIfNeeded(install: install, fileManager: fileManager)

        let defaultSet = try loadOrCreateDefaultSet(
            install: install,
            currentMods: currentMods,
            fileManager: fileManager
        )

        let userSetURLs = try fileManager.contentsOfDirectory(
            at: install.modSetDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "plist" }
        .filter { $0.deletingPathExtension().lastPathComponent != defaultSetID }

        let userSets: [ModSet] = userSetURLs.compactMap { url in
            guard let stored = loadStoredSet(at: url) else {
                return nil
            }

            return ModSet(
                id: stored.id,
                name: stored.name,
                disabledFolderNames: normalizeFolderNames(stored.disabledFolderNames),
                isDefault: false
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return [defaultSet] + userSets
    }

    public static func createSet(
        named name: String,
        from sourceSet: ModSet,
        existingSets: [ModSet]
    ) throws -> ModSet {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return ModSet(
                id: UUID().uuidString,
                name: "Untitled Set",
                disabledFolderNames: normalizeFolderNames(sourceSet.disabledFolderNames),
                isDefault: false
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
            isDefault: false
        )
    }

    public static func saveSet(
        _ set: ModSet,
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws {
        guard !set.isDefault else {
            throw ModSetStoreError.cannotModifyDefaultSet
        }

        try createStoreDirectoryIfNeeded(install: install, fileManager: fileManager)
        let storedSet = StoredModSet(
            id: set.id,
            name: set.name,
            disabledFolderNames: normalizeFolderNames(set.disabledFolderNames)
        )
        try saveStoredSet(
            storedSet,
            to: urlForSetID(set.id, install: install),
            fileManager: fileManager
        )
    }

    public static func deleteSet(
        _ set: ModSet,
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws {
        guard !set.isDefault else {
            throw ModSetStoreError.cannotModifyDefaultSet
        }

        let url = urlForSetID(set.id, install: install)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ModSetStoreError.missingSet(set.id)
        }

        try fileManager.removeItem(at: url)
    }

    @discardableResult
    public static func applySet(
        _ set: ModSet,
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> Int {
        let mods = try ModLibrary.scan(install: install, fileManager: fileManager)
        let disabledFolderNames = Set(
            normalizeFolderNames(set.disabledFolderNames).map(\.normalizedFolderToken)
        )

        var changedCount = 0
        for mod in mods {
            let shouldBeEnabled = !disabledFolderNames.contains(mod.enabledFolderName.normalizedFolderToken)
            guard mod.isEnabled != shouldBeEnabled else {
                continue
            }

            _ = try ModLibrary.setEnabled(mod, enabled: shouldBeEnabled, fileManager: fileManager)
            changedCount += 1
        }

        return changedCount
    }

    public static func snapshotSet(
        id: String,
        name: String,
        from mods: [ModInfo],
        isDefault: Bool = false
    ) -> ModSet {
        ModSet(
            id: id,
            name: name,
            disabledFolderNames: normalizeFolderNames(
                mods.filter { !$0.isEnabled }.map(\.enabledFolderName)
            ),
            isDefault: isDefault
        )
    }

    private struct StoredModSet: Codable {
        var id: String
        var name: String
        var disabledFolderNames: [String]
    }

    private static func loadOrCreateDefaultSet(
        install: StardewInstall,
        currentMods: [ModInfo],
        fileManager: FileManager
    ) throws -> ModSet {
        let defaultURL = urlForSetID(defaultSetID, install: install)
        if let stored = loadStoredSet(at: defaultURL) {
            return ModSet(
                id: defaultSetID,
                name: defaultSetName,
                disabledFolderNames: normalizeFolderNames(stored.disabledFolderNames),
                isDefault: true
            )
        }

        let baselineSet = snapshotSet(
            id: defaultSetID,
            name: defaultSetName,
            from: currentMods,
            isDefault: true
        )

        let storedSet = StoredModSet(
            id: baselineSet.id,
            name: baselineSet.name,
            disabledFolderNames: baselineSet.disabledFolderNames
        )
        try saveStoredSet(storedSet, to: defaultURL, fileManager: fileManager)
        return baselineSet
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

    private static func loadStoredSet(at url: URL) -> StoredModSet? {
        guard
            let data = try? Data(contentsOf: url),
            let storedSet = try? PropertyListDecoder().decode(StoredModSet.self, from: data)
        else {
            return nil
        }

        return storedSet
    }

    private static func saveStoredSet(
        _ storedSet: StoredModSet,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(storedSet)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
    }

    private static func urlForSetID(_ setID: String, install: StardewInstall) -> URL {
        install.modSetDirectoryURL.appendingPathComponent("\(setID).plist")
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

private extension String {
    var normalizedFolderToken: String {
        trimmingPrefix(Character(".")).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedDependencyID: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedSearchText: String {
        lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    var compactSearchText: String {
        normalizedSearchText.replacingOccurrences(of: " ", with: "")
    }

    func matchesSearchValue(_ value: String) -> Bool {
        let normalizedValue = value.normalizedSearchText
        guard !normalizedValue.isEmpty else {
            return true
        }

        return normalizedSearchText.contains(normalizedValue)
            || compactSearchText.contains(value.compactSearchText)
    }

    func trimmingPrefix(_ prefix: Character) -> String {
        var value = self
        while value.first == prefix {
            value.removeFirst()
        }
        return value
    }
}

private extension Array where Element == ModInfo {
    func withResolvedRequiredDependencies() -> [ModInfo] {
        let enabledUniqueIDs: Set<String> = Set(
            compactMap { mod in
                guard mod.isEnabled else {
                    return nil
                }
                return mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID
            }
        )

        var resolvedMods = self

        for index in resolvedMods.indices {
            guard resolvedMods[index].isEnabled else {
                resolvedMods[index].missingRequiredDependencyIDs = []
                resolvedMods[index].missingOptionalDependencyIDs = []
                continue
            }

            let ownUniqueID = resolvedMods[index].manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID
            let dependencies = resolvedMods[index].manifest?.dependencies ?? []

            var requiredIDs: [String] = []
            if let contentPackTarget = resolvedMods[index].manifest?.contentPackFor?.uniqueID?.trimmedNonEmpty {
                requiredIDs.append(contentPackTarget)
            }

            requiredIDs.append(contentsOf: dependencies.compactMap { dependency in
                guard dependency.isRequired != false else {
                    return nil
                }
                return dependency.uniqueID?.trimmedNonEmpty
            })

            let optionalIDs: [String] = dependencies.compactMap { dependency in
                guard dependency.isRequired == false else {
                    return nil
                }
                return dependency.uniqueID?.trimmedNonEmpty
            }

            var missingIDs: [String] = []
            var seenMissingIDs: Set<String> = []

            for requiredID in requiredIDs {
                let normalizedRequiredID = requiredID.normalizedDependencyID
                if normalizedRequiredID.isEmpty || normalizedRequiredID == ownUniqueID {
                    continue
                }
                guard !enabledUniqueIDs.contains(normalizedRequiredID) else {
                    continue
                }
                guard !seenMissingIDs.contains(normalizedRequiredID) else {
                    continue
                }

                seenMissingIDs.insert(normalizedRequiredID)
                missingIDs.append(requiredID)
            }

            var missingOptionalIDs: [String] = []
            var seenMissingOptionalIDs: Set<String> = []

            for optionalID in optionalIDs {
                let normalizedOptionalID = optionalID.normalizedDependencyID
                if normalizedOptionalID.isEmpty || normalizedOptionalID == ownUniqueID {
                    continue
                }
                if seenMissingIDs.contains(normalizedOptionalID) {
                    continue
                }
                guard !enabledUniqueIDs.contains(normalizedOptionalID) else {
                    continue
                }
                guard !seenMissingOptionalIDs.contains(normalizedOptionalID) else {
                    continue
                }

                seenMissingOptionalIDs.insert(normalizedOptionalID)
                missingOptionalIDs.append(optionalID)
            }

            resolvedMods[index].missingRequiredDependencyIDs = missingIDs
            resolvedMods[index].missingOptionalDependencyIDs = missingOptionalIDs
        }

        return resolvedMods
    }
}
