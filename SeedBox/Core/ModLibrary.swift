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
            return AppStrings.Errors.modFolderDoesNotExist(at: url.path)
        case .destinationExists(let url):
            return AppStrings.Errors.modAlreadyExists(at: url.path)
        case .modAlreadyInstalled(let folderName, let url):
            return AppStrings.Errors.modAlreadyInstalled(folderName: folderName, path: url.path)
        case .invalidDisabledName(let name):
            return AppStrings.Errors.disabledFolderNameCannotBeEnabled(name)
        case .noInstallableMods(let url):
            return AppStrings.Errors.noInstallableMods(at: url.path)
        }
    }
}

struct InstalledModResult: Equatable, Sendable {
    var sourceURL: URL
    var destinationURL: URL
    var displayName: String
    var version: String?
}

struct UpdatedModResult: Equatable, Sendable {
    var sourceURL: URL
    var destinationURL: URL
    var archivedURL: URL
    var displayName: String
    var previousVersion: String?
    var installedVersion: String?
}

struct SkippedModInstallResult: Equatable, Sendable {
    var sourceURL: URL
    var existingURL: URL?
    var displayName: String
    var selectedVersion: String?
    var existingVersion: String?
    var reason: SkippedModInstallReason
}

enum SkippedModInstallReason: Equatable, Sendable {
    case alreadyInstalled
    case duplicateInSelection
}

struct ModInstallResult: Equatable, Sendable {
    var installed: [InstalledModResult] = []
    var updated: [UpdatedModResult] = []
    var skipped: [SkippedModInstallResult] = []

    var installedURLs: [URL] {
        installed.map(\.destinationURL) + updated.map(\.destinationURL)
    }

    var didChangeInstalledMods: Bool {
        !installed.isEmpty || !updated.isEmpty
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

        let sortedMods = disambiguatedIDs(for: scannedMods)
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        return ModDependencyGraph(mods: sortedMods).resolvedMods()
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
        archiveDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModInstallResult {
        guard fileManager.directoryExists(at: install.modDirectoryURL) else {
            throw ModLibraryError.modFolderMissing(install.modDirectoryURL)
        }

        let resolvedArchiveDirectory = archiveDirectory ?? install.archivedModsDirectoryURL
        var result = ModInstallResult()
        var pendingOperations: [PendingInstallOperation] = []
        var pendingIdentities: Set<ModInstallIdentity> = []
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
        let installedMods = installedModLocations(
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
                let candidateIdentity = installIdentity(for: candidate)
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
                let operationIdentity = candidateIdentity ?? .folderToken(destinationToken)

                guard !pendingIdentities.contains(operationIdentity) else {
                    result.skipped.append(
                        skippedResult(
                            for: candidate,
                            existingURL: pendingDestinationURLsByToken[destinationToken],
                            reason: .duplicateInSelection
                        )
                    )
                    continue
                }

                if let existingMod = matchingInstalledMod(
                    for: candidate,
                    destinationToken: destinationToken,
                    installedMods: installedMods
                ) {
                    if shouldUpdate(candidate: candidate, existingMod: existingMod) {
                        pendingIdentities.insert(operationIdentity)
                        pendingOperations.append(
                            .update(
                                candidate: candidate,
                                existingMod: existingMod
                            )
                        )
                    } else {
                        result.skipped.append(
                            skippedResult(
                                for: candidate,
                                existingMod: existingMod,
                                reason: .alreadyInstalled
                            )
                        )
                    }
                    continue
                }

                if fileManager.fileExists(atPath: destinationURL.path),
                   !fileManager.directoryExists(at: destinationURL) {
                    throw ModLibraryError.destinationExists(destinationURL)
                }

                if let existingURL = existingModURLsByToken[destinationToken] {
                    result.skipped.append(
                        skippedResult(
                            for: candidate,
                            existingURL: existingURL,
                            reason: .alreadyInstalled
                        )
                    )
                    continue
                }

                if let pendingDestinationURL = pendingDestinationURLsByToken[destinationToken] {
                    result.skipped.append(
                        skippedResult(
                            for: candidate,
                            existingURL: pendingDestinationURL,
                            reason: .duplicateInSelection
                        )
                    )
                    continue
                }

                pendingIdentities.insert(operationIdentity)
                pendingDestinationURLsByToken[destinationToken] = destinationURL
                pendingOperations.append(.install(candidate: candidate, destinationURL: destinationURL))
            }
        }

        var completedOperations: [CompletedInstallOperation] = []
        do {
            for pendingOperation in pendingOperations {
                switch pendingOperation {
                case .install(let candidate, let destinationURL):
                    try fileManager.copyItem(at: candidate.sourceURL, to: destinationURL)
                    result.installed.append(
                        InstalledModResult(
                            sourceURL: candidate.sourceURL,
                            destinationURL: destinationURL,
                            displayName: displayName(for: candidate),
                            version: candidate.manifest?.version?.trimmedNonEmpty
                        )
                    )
                    completedOperations.append(.installed(destinationURL))
                case .update(let candidate, let existingMod):
                    let archivedURL = try ModArchive.archive(
                        existingMod.url,
                        in: resolvedArchiveDirectory,
                        reason: .updated,
                        fileManager: fileManager
                    )
                    do {
                        try fileManager.copyItem(at: candidate.sourceURL, to: existingMod.url)
                    } catch {
                        try? fileManager.moveItem(at: archivedURL, to: existingMod.url)
                        throw error
                    }
                    result.updated.append(
                        UpdatedModResult(
                            sourceURL: candidate.sourceURL,
                            destinationURL: existingMod.url,
                            archivedURL: archivedURL,
                            displayName: displayName(for: candidate, fallback: existingMod.displayName),
                            previousVersion: existingMod.version,
                            installedVersion: candidate.manifest?.version?.trimmedNonEmpty
                        )
                    )
                    completedOperations.append(.updated(destinationURL: existingMod.url, archivedURL: archivedURL))
                }
            }
        } catch {
            for completedOperation in completedOperations.reversed() {
                switch completedOperation {
                case .installed(let destinationURL):
                    try? fileManager.removeItem(at: destinationURL)
                case .updated(let destinationURL, let archivedURL):
                    try? fileManager.removeItem(at: destinationURL)
                    try? fileManager.moveItem(at: archivedURL, to: destinationURL)
                }
            }
            throw error
        }

        return result
    }

    static func archive(
        _ mod: ModInfo,
        in archiveDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try ModArchive.archive(
            mod.url,
            in: archiveDirectory,
            reason: .deleted,
            fileManager: fileManager
        )
    }

    private struct InstallSource {
        var candidates: [InstallCandidate]
        var temporaryExtractionDirectory: URL?
    }

    private struct InstallCandidate {
        var sourceURL: URL
        var destinationFolderName: String
        var manifest: ModManifest?
    }

    private struct InstalledModLocation {
        var url: URL
        var folderName: String
        var manifest: ModManifest?

        var displayName: String {
            manifest?.name ?? folderName.trimmingPrefix(Character("."))
        }

        var version: String? {
            manifest?.version?.trimmedNonEmpty
        }

        var normalizedUniqueID: String? {
            manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID
        }
    }

    private enum ModInstallIdentity: Hashable {
        case uniqueID(String)
        case folderToken(String)
    }

    private enum PendingInstallOperation {
        case install(candidate: InstallCandidate, destinationURL: URL)
        case update(candidate: InstallCandidate, existingMod: InstalledModLocation)
    }

    private enum CompletedInstallOperation {
        case installed(URL)
        case updated(destinationURL: URL, archivedURL: URL)
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
                    destinationFolderName: rootDestinationFolderName ?? sourceURL.lastPathComponent,
                    manifest: loadManifest(at: sourceURL.appendingPathComponent("manifest.json"))
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
                        destinationFolderName: childURL.lastPathComponent,
                        manifest: loadManifest(at: childURL.appendingPathComponent("manifest.json"))
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

    private static func matchingInstalledMod(
        for candidate: InstallCandidate,
        destinationToken: String,
        installedMods: [InstalledModLocation]
    ) -> InstalledModLocation? {
        if let candidateUniqueID = candidate.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
           let match = installedMods.first(where: { installedMod in
               installedMod.normalizedUniqueID == candidateUniqueID
           }) {
            return match
        }

        return installedMods.first { installedMod in
            installedMod.folderName.normalizedFolderToken == destinationToken
        }
    }

    private static func installIdentity(for candidate: InstallCandidate) -> ModInstallIdentity? {
        guard let uniqueID = candidate.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
              !uniqueID.isEmpty
        else {
            return nil
        }

        return .uniqueID(uniqueID)
    }

    private static func shouldUpdate(
        candidate: InstallCandidate,
        existingMod: InstalledModLocation
    ) -> Bool {
        guard let candidateVersion = candidate.manifest?.version?.trimmedNonEmpty,
              let existingVersion = existingMod.version
        else {
            return false
        }

        return ModVersionComparator.compare(candidateVersion, to: existingVersion) == .orderedDescending
    }

    private static func skippedResult(
        for candidate: InstallCandidate,
        existingMod: InstalledModLocation,
        reason: SkippedModInstallReason
    ) -> SkippedModInstallResult {
        skippedResult(
            for: candidate,
            existingURL: existingMod.url,
            existingVersion: existingMod.version,
            fallbackName: existingMod.displayName,
            reason: reason
        )
    }

    private static func skippedResult(
        for candidate: InstallCandidate,
        existingURL: URL?,
        existingVersion: String? = nil,
        fallbackName: String? = nil,
        reason: SkippedModInstallReason
    ) -> SkippedModInstallResult {
        SkippedModInstallResult(
            sourceURL: candidate.sourceURL,
            existingURL: existingURL,
            displayName: displayName(for: candidate, fallback: fallbackName),
            selectedVersion: candidate.manifest?.version?.trimmedNonEmpty,
            existingVersion: existingVersion,
            reason: reason
        )
    }

    private static func displayName(
        for candidate: InstallCandidate,
        fallback: String? = nil
    ) -> String {
        candidate.manifest?.name?.trimmedNonEmpty
            ?? fallback
            ?? candidate.destinationFolderName.trimmingPrefix(Character("."))
    }

    private static func installedModLocations(
        in modsDirectory: URL,
        fileManager: FileManager
    ) -> [InstalledModLocation] {
        let installedURLs = (try? fileManager.contentsOfDirectory(
            at: modsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []

        return installedURLs
            .filter { fileManager.directoryExists(at: $0) }
            .map { installedURL in
                InstalledModLocation(
                    url: installedURL,
                    folderName: installedURL.lastPathComponent,
                    manifest: findManifest(in: installedURL, fileManager: fileManager)
                        .flatMap { loadManifest(at: $0) }
                )
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
