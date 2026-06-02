import Foundation
import ZIPFoundation

enum ModLibraryError: Error, Equatable, LocalizedError, Sendable {
    case modFolderMissing(URL)
    case destinationExists(URL)
    case modAlreadyInstalled(String, URL)
    case invalidDisabledName(String)
    case noInstallableMods(URL)

    var errorDescription: String? {
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

enum ModLibrary {
    private static let maximumInstallSearchDepth = 8

    static func scan(
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

        let scannedMods = folders.map { url in
            let manifestURL = findManifest(in: url, fileManager: fileManager)
            return ModInfo(
                folderName: url.lastPathComponent,
                url: url,
                isEnabled: !url.lastPathComponent.hasPrefix("."),
                manifest: manifestURL.flatMap { loadManifest(at: $0) }
            )
        }

        return disambiguatedIDs(for: scannedMods)
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .withResolvedRequiredDependencies()
    }

    static func setEnabled(
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

    static func installMods(
        from sourceURLs: [URL],
        into install: StardewInstall,
        enabled: Bool = true,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard fileManager.directoryExists(at: install.modDirectoryURL) else {
            throw ModLibraryError.modFolderMissing(install.modDirectoryURL)
        }

        var pendingInstalls: [(sourceURL: URL, destinationURL: URL)] = []
        var pendingDestinationURLsByToken: [String: URL] = [:]
        var temporaryExtractionDirectories: [URL] = []
        defer {
            for temporaryExtractionDirectory in temporaryExtractionDirectories {
                try? fileManager.removeItem(at: temporaryExtractionDirectory)
            }
        }

        let existingModURLsByToken = installedModURLsByToken(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )

        for sourceURL in sourceURLs {
            let installSource = try resolveInstallSource(from: sourceURL, fileManager: fileManager)
            if let temporaryExtractionDirectory = installSource.temporaryExtractionDirectory {
                temporaryExtractionDirectories.append(temporaryExtractionDirectory)
            }

            guard !installSource.candidates.isEmpty else {
                throw ModLibraryError.noInstallableMods(sourceURL)
            }

            for candidate in installSource.candidates {
                let destinationFolderName = destinationFolderName(
                    for: candidate.destinationFolderName,
                    enabled: enabled
                )
                let folderName = destinationFolderName.trimmingPrefix(Character("."))
                guard !folderName.isEmpty else {
                    throw ModLibraryError.invalidDisabledName(candidate.destinationFolderName)
                }

                let destinationURL = install.modDirectoryURL
                    .appendingPathComponent(destinationFolderName)
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
                pendingInstalls.append((candidate.sourceURL, destinationURL))
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

    static func trash(
        _ mod: ModInfo,
        fileManager: FileManager = .default
    ) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(
            at: mod.url,
            resultingItemURL: &resultingURL
        )
    }

    private struct InstallSource {
        var candidates: [InstallCandidate]
        var temporaryExtractionDirectory: URL?
    }

    private struct InstallCandidate {
        var sourceURL: URL
        var destinationFolderName: String
    }

    private static func resolveInstallSource(
        from sourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> InstallSource {
        guard sourceURL.pathExtension.lowercased() == "zip" else {
            return InstallSource(
                candidates: installCandidates(from: sourceURL, fileManager: fileManager),
                temporaryExtractionDirectory: nil
            )
        }

        let extractionDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("SeedBoxZip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try fileManager.unzipItem(at: sourceURL, to: extractionDirectory)

        return InstallSource(
            candidates: installCandidates(
                from: extractionDirectory,
                rootDestinationFolderName: sourceURL.deletingPathExtension().lastPathComponent,
                fileManager: fileManager
            ),
            temporaryExtractionDirectory: extractionDirectory
        )
    }

    private static func installCandidates(
        from sourceURL: URL,
        rootDestinationFolderName: String? = nil,
        fileManager: FileManager
    ) -> [InstallCandidate] {
        guard fileManager.directoryExists(at: sourceURL) else {
            return []
        }

        if containsManifest(in: sourceURL, fileManager: fileManager) {
            return [
                InstallCandidate(
                    sourceURL: sourceURL,
                    destinationFolderName: rootDestinationFolderName ?? sourceURL.lastPathComponent
                )
            ]
        }

        return nestedInstallCandidates(
            in: sourceURL,
            remainingDepth: maximumInstallSearchDepth,
            fileManager: fileManager
        )
    }

    private static func nestedInstallCandidates(
        in directoryURL: URL,
        remainingDepth: Int,
        fileManager: FileManager
    ) -> [InstallCandidate] {
        guard remainingDepth > 0 else {
            return []
        }

        let children = directoryChildren(in: directoryURL, fileManager: fileManager)
        return children.flatMap { childURL -> [InstallCandidate] in
            guard fileManager.directoryExists(at: childURL),
                  !shouldSkipInstallSearchDirectory(childURL)
            else {
                return []
            }

            if containsManifest(in: childURL, fileManager: fileManager) {
                return [
                    InstallCandidate(
                        sourceURL: childURL,
                        destinationFolderName: childURL.lastPathComponent
                    )
                ]
            }

            return nestedInstallCandidates(
                in: childURL,
                remainingDepth: remainingDepth - 1,
                fileManager: fileManager
            )
        }
    }

    private static func containsManifest(
        in directoryURL: URL,
        fileManager: FileManager
    ) -> Bool {
        fileManager.fileExists(atPath: directoryURL.appendingPathComponent("manifest.json").path)
    }

    private static func directoryChildren(
        in directoryURL: URL,
        fileManager: FileManager
    ) -> [URL] {
        let children = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []

        return children.sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
    }

    private static func shouldSkipInstallSearchDirectory(_ directoryURL: URL) -> Bool {
        switch directoryURL.lastPathComponent {
        case "__MACOSX", ".git", ".hg", ".svn":
            return true
        default:
            return false
        }
    }

    private static func destinationFolderName(
        for sourceFolderName: String,
        enabled: Bool
    ) -> String {
        let enabledFolderName = sourceFolderName.trimmingPrefix(Character("."))
        return enabled ? enabledFolderName : ".\(enabledFolderName)"
    }

    private static func disambiguatedIDs(for mods: [ModInfo]) -> [ModInfo] {
        let duplicateIDs = Dictionary(grouping: mods, by: \.id)
            .filter { $0.value.count > 1 }
            .keys

        guard !duplicateIDs.isEmpty else {
            return mods
        }

        return mods.map { mod in
            guard duplicateIDs.contains(mod.id) else {
                return mod
            }

            var disambiguatedMod = mod
            disambiguatedMod.id = "\(mod.id)#\(mod.folderName)"
            return disambiguatedMod
        }
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
