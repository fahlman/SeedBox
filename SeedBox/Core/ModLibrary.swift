import Foundation

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

enum ModLibrary {
    static func scan(
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> [ModInfo] {
        try scanWithDiagnostics(install: install, fileManager: fileManager).mods
    }

    static func scanWithDiagnostics(
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> ModLibraryScanResult {
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

        var invalidFolders: [InvalidModFolder] = []
        let scannedMods = folders.compactMap { url -> ModInfo? in
            let manifestURL = ModManifestReader.findManifest(in: url, fileManager: fileManager)
            guard let manifestURL else {
                invalidFolders.append(
                    InvalidModFolder(
                        url: url,
                        folderName: url.lastPathComponent,
                        reason: AppStrings.Problems.missingManifest
                    )
                )
                return nil
            }

            return ModInfo(
                folderName: url.lastPathComponent,
                url: url,
                isEnabled: !url.lastPathComponent.hasPrefix("."),
                manifest: ModManifestReader.loadManifest(at: manifestURL)
            )
        }

        let sortedMods = disambiguatedIDs(for: scannedMods)
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        let sortedInvalidFolders = invalidFolders.sorted { lhs, rhs in
            lhs.folderName.localizedCaseInsensitiveCompare(rhs.folderName) == .orderedAscending
        }

        return ModLibraryScanResult(
            mods: ModDependencyGraph(mods: sortedMods).resolvedMods(),
            invalidFolders: sortedInvalidFolders
        )
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
        replacementPolicy: ModInstallReplacementPolicy = .newerOnly,
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

        let existingModURLsByToken = ModInstalledCatalog.urlsByToken(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )
        let installedMods = ModInstalledCatalog.locations(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )

        for sourceURL in sourceURLs {
            let installSource = try ModInstallSourceResolver.resolve(from: sourceURL, fileManager: fileManager)
            if let temporaryExtractionDirectory = installSource.temporaryExtractionDirectory {
                temporaryExtractionDirectories.append(temporaryExtractionDirectory)
            }

            guard !installSource.candidates.isEmpty else {
                throw ModLibraryError.noInstallableMods(sourceURL)
            }

            for candidate in installSource.candidates {
                let candidateIdentity = ModInstallPlanner.identity(for: candidate)
                let destinationFolderName = ModInstallPlanner.destinationFolderName(
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
                        ModInstallPlanner.skippedResult(
                            for: candidate,
                            existingURL: pendingDestinationURLsByToken[destinationToken],
                            reason: .duplicateInSelection
                        )
                    )
                    continue
                }

                if let existingMod = ModInstalledCatalog.matchingInstalledMod(
                    for: candidate,
                    destinationToken: destinationToken,
                    installedMods: installedMods
                ) {
                    if ModInstallPlanner.sameFileURL(candidate.sourceURL, existingMod.url) {
                        result.skipped.append(
                            ModInstallPlanner.skippedResult(
                                for: candidate,
                                existingMod: existingMod,
                                reason: .alreadyInstalled
                            )
                        )
                    } else if ModInstallPlanner.shouldReplace(
                        candidate: candidate,
                        existingMod: existingMod,
                        policy: replacementPolicy
                    ) {
                        pendingIdentities.insert(operationIdentity)
                        pendingOperations.append(
                            .update(
                                candidate: candidate,
                                existingMod: existingMod,
                                replacementKind: ModInstallPlanner.replacementKind(candidate: candidate, existingMod: existingMod)
                            )
                        )
                    } else {
                        result.skipped.append(
                            ModInstallPlanner.skippedResult(
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
                        ModInstallPlanner.skippedResult(
                            for: candidate,
                            existingURL: existingURL,
                            reason: .alreadyInstalled
                        )
                    )
                    continue
                }

                if let pendingDestinationURL = pendingDestinationURLsByToken[destinationToken] {
                    result.skipped.append(
                        ModInstallPlanner.skippedResult(
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
                            displayName: ModInstallPlanner.displayName(for: candidate),
                            version: candidate.manifest?.version?.trimmedNonEmpty
                        )
                    )
                    completedOperations.append(.installed(destinationURL))
                case .update(let candidate, let existingMod, let replacementKind):
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
                            displayName: ModInstallPlanner.displayName(for: candidate, fallback: existingMod.displayName),
                            previousVersion: existingMod.version,
                            installedVersion: candidate.manifest?.version?.trimmedNonEmpty,
                            replacementKind: replacementKind
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

    static func previewImport(
        from sourceURLs: [URL],
        into install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> ModImportPreview {
        guard fileManager.directoryExists(at: install.modDirectoryURL) else {
            throw ModLibraryError.modFolderMissing(install.modDirectoryURL)
        }

        var items: [ModImportPreviewItem] = []
        var pendingIdentities: Set<ModInstallIdentity> = []
        var pendingDestinationURLsByToken: [String: URL] = [:]
        var temporaryExtractionDirectories: [URL] = []

        let existingModURLsByToken = ModInstalledCatalog.urlsByToken(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )
        let installedMods = ModInstalledCatalog.locations(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )

        for sourceURL in sourceURLs {
            let installSource = try ModInstallSourceResolver.resolve(from: sourceURL, fileManager: fileManager)
            if let temporaryExtractionDirectory = installSource.temporaryExtractionDirectory {
                temporaryExtractionDirectories.append(temporaryExtractionDirectory)
            }

            guard !installSource.candidates.isEmpty else {
                throw ModLibraryError.noInstallableMods(sourceURL)
            }

            for candidate in installSource.candidates {
                let destinationFolderName = ModInstallPlanner.destinationFolderName(
                    for: candidate.destinationFolderName,
                    enabled: true
                )
                let folderName = destinationFolderName.trimmingPrefix(Character("."))
                guard !folderName.isEmpty else {
                    throw ModLibraryError.invalidDisabledName(candidate.destinationFolderName)
                }

                let destinationToken = folderName.normalizedFolderToken
                let operationIdentity = ModInstallPlanner.identity(for: candidate) ?? .folderToken(destinationToken)
                let action: ModImportPreviewAction
                let existingMod: InstalledModLocation?

                if pendingIdentities.contains(operationIdentity)
                    || pendingDestinationURLsByToken[destinationToken] != nil {
                    existingMod = nil
                    action = .duplicateInSelection
                } else if let match = ModInstalledCatalog.matchingInstalledMod(
                    for: candidate,
                    destinationToken: destinationToken,
                    installedMods: installedMods
                ) {
                    existingMod = match
                    action = ModInstallPlanner.sameFileURL(candidate.sourceURL, match.url)
                        ? .alreadyInstalled
                        : ModInstallPlanner.previewAction(candidate: candidate, existingMod: match)
                    pendingIdentities.insert(operationIdentity)
                } else if let existingURL = existingModURLsByToken[destinationToken] {
                    existingMod = InstalledModLocation(url: existingURL, folderName: existingURL.lastPathComponent, manifest: nil)
                    action = .alreadyInstalled
                    pendingIdentities.insert(operationIdentity)
                } else {
                    existingMod = nil
                    action = .install
                    pendingIdentities.insert(operationIdentity)
                    pendingDestinationURLsByToken[destinationToken] = install.modDirectoryURL
                        .appendingPathComponent(destinationFolderName)
                }

                items.append(
                    ModImportPreviewItem(
                        sourceURL: candidate.sourceURL,
                        displayName: ModInstallPlanner.displayName(for: candidate, fallback: existingMod?.displayName),
                        selectedVersion: candidate.manifest?.version?.trimmedNonEmpty,
                        existingVersion: existingMod?.version,
                        destinationFolderName: destinationFolderName,
                        existingFolderName: existingMod?.folderName,
                        action: action,
                        typeText: ModInstallPlanner.typeText(for: candidate.manifest)
                    )
                )
            }
        }

        return ModImportPreview(
            sourceURLs: sourceURLs,
            items: items,
            temporaryExtractionDirectories: temporaryExtractionDirectories
        )
    }

    static func installPreview(
        _ preview: ModImportPreview,
        into install: StardewInstall,
        enabled: Bool = true,
        archiveDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModInstallResult {
        try installMods(
            from: preview.installableItems.map(\.sourceURL),
            into: install,
            enabled: enabled,
            replacementPolicy: .replaceExisting,
            archiveDirectory: archiveDirectory,
            fileManager: fileManager
        )
    }

    static func discardImportPreview(
        _ preview: ModImportPreview,
        fileManager: FileManager = .default
    ) {
        for temporaryExtractionDirectory in preview.temporaryExtractionDirectories {
            try? fileManager.removeItem(at: temporaryExtractionDirectory)
        }
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

    static func restoreArchivedMods(
        _ archivedMods: [ArchivedModInfo],
        into install: StardewInstall,
        archiveDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> [RestoredModResult] {
        guard fileManager.directoryExists(at: install.modDirectoryURL) else {
            throw ModLibraryError.modFolderMissing(install.modDirectoryURL)
        }

        let resolvedArchiveDirectory = archiveDirectory ?? install.archivedModsDirectoryURL
        var results: [RestoredModResult] = []
        var completedOperations: [CompletedRestoreOperation] = []

        do {
            for archivedMod in archivedMods {
                guard fileManager.directoryExists(at: archivedMod.url) else {
                    throw ModLibraryError.modFolderMissing(archivedMod.url)
                }

                let currentLocations = ModInstalledCatalog.locations(
                    in: install.modDirectoryURL,
                    fileManager: fileManager
                )
                let destinationToken = archivedMod.enabledFolderName.normalizedFolderToken
                let matchingLocation = ModInstalledCatalog.matchingInstalledMod(
                    for: archivedMod,
                    destinationToken: destinationToken,
                    installedMods: currentLocations
                )
                let destinationURL = matchingLocation?.url
                    ?? install.modDirectoryURL.appendingPathComponent(archivedMod.folderName)

                if fileManager.fileExists(atPath: destinationURL.path),
                   matchingLocation == nil,
                   !fileManager.directoryExists(at: destinationURL) {
                    throw ModLibraryError.destinationExists(destinationURL)
                }

                let archivedCurrentURL: URL?
                if let matchingLocation {
                    archivedCurrentURL = try ModArchive.archive(
                        matchingLocation.url,
                        in: resolvedArchiveDirectory,
                        reason: .updated,
                        fileManager: fileManager
                    )
                } else if fileManager.directoryExists(at: destinationURL) {
                    archivedCurrentURL = try ModArchive.archive(
                        destinationURL,
                        in: resolvedArchiveDirectory,
                        reason: .updated,
                        fileManager: fileManager
                    )
                } else {
                    archivedCurrentURL = nil
                }

                do {
                    try fileManager.moveItem(at: archivedMod.url, to: destinationURL)
                    removeEmptyArchiveContainerIfNeeded(
                        archivedMod.containerURL,
                        archiveDirectory: resolvedArchiveDirectory,
                        fileManager: fileManager
                    )
                } catch {
                    if let archivedCurrentURL {
                        try? fileManager.moveItem(at: archivedCurrentURL, to: destinationURL)
                    }
                    throw error
                }

                results.append(
                    RestoredModResult(
                        sourceURL: archivedMod.url,
                        destinationURL: destinationURL,
                        archivedCurrentURL: archivedCurrentURL,
                        displayName: archivedMod.displayName,
                        version: archivedMod.manifest?.version?.trimmedNonEmpty
                    )
                )
                completedOperations.append(
                    .restored(
                        sourceURL: archivedMod.url,
                        sourceContainerURL: archivedMod.containerURL,
                        destinationURL: destinationURL,
                        archivedCurrentURL: archivedCurrentURL
                    )
                )
            }
        } catch {
            for operation in completedOperations.reversed() {
                try? fileManager.createDirectory(
                    at: operation.sourceContainerURL,
                    withIntermediateDirectories: true
                )
                try? fileManager.moveItem(at: operation.destinationURL, to: operation.sourceURL)
                if let archivedCurrentURL = operation.archivedCurrentURL {
                    try? fileManager.moveItem(at: archivedCurrentURL, to: operation.destinationURL)
                }
            }
            throw error
        }

        return results
    }

    private enum PendingInstallOperation {
        case install(candidate: ModInstallCandidate, destinationURL: URL)
        case update(candidate: ModInstallCandidate, existingMod: InstalledModLocation, replacementKind: ModReplacementKind)
    }

    private enum CompletedInstallOperation {
        case installed(URL)
        case updated(destinationURL: URL, archivedURL: URL)
    }

    private struct CompletedRestoreOperation {
        var sourceURL: URL
        var sourceContainerURL: URL
        var destinationURL: URL
        var archivedCurrentURL: URL?

        static func restored(
            sourceURL: URL,
            sourceContainerURL: URL,
            destinationURL: URL,
            archivedCurrentURL: URL?
        ) -> Self {
            Self(
                sourceURL: sourceURL,
                sourceContainerURL: sourceContainerURL,
                destinationURL: destinationURL,
                archivedCurrentURL: archivedCurrentURL
            )
        }
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

    private static func removeEmptyArchiveContainerIfNeeded(
        _ containerURL: URL,
        archiveDirectory: URL,
        fileManager: FileManager
    ) {
        guard containerURL.deletingLastPathComponent().standardizedFileURL == archiveDirectory.standardizedFileURL,
              let children = try? fileManager.contentsOfDirectory(
                at: containerURL,
                includingPropertiesForKeys: nil
              ),
              children.isEmpty
        else {
            return
        }

        try? fileManager.removeItem(at: containerURL)
    }

}
