import Foundation

enum ModLibraryError: Error, Equatable, LocalizedError, Sendable {
    case modFolderMissing(URL)
    case destinationExists(URL)
    case modAlreadyInstalled(String, URL)
    case invalidDisabledName(String)
    case noInstallableMods(URL)
    case archivedModOutsideArchive(URL)

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
        case .archivedModOutsideArchive(let url):
            return AppStrings.Errors.archivedModOutsideArchive(at: url.path)
        }
    }
}

struct ModEnabledStateChange {
    var mod: ModInfo
    var destinationURL: URL
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
        try FileMoveTransaction.recoverIfNeeded(
            context: install.fileMoveTransactionContext(),
            fileManager: fileManager
        )
        try ModInstallWorkflow.removeAbandonedStagingDirectories(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )

        var invalidFolders: [InvalidModFolder] = []
        var folders: [URL] = []
        for url in try fileManager.contentsOfDirectory(
            at: install.modDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) {
            guard url.lastPathComponent != ".DS_Store" else {
                continue
            }

            let isSymbolicLink = (try? url.resourceValues(
                forKeys: [.isSymbolicLinkKey]
            ).isSymbolicLink) ?? false
            guard !isSymbolicLink else {
                // Deleting or renaming a linked folder would silently operate on
                // whatever it points at, so linked folders are surfaced instead
                // of managed.
                if fileManager.directoryExists(at: url) {
                    invalidFolders.append(
                        InvalidModFolder(
                            url: url,
                            folderName: url.lastPathComponent,
                            reason: AppStrings.Problems.linkedFolder
                        )
                    )
                }
                continue
            }

            if fileManager.directoryExists(at: url) {
                folders.append(url)
            }
        }
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
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard mod.isEnabled != enabled else {
            return mod.url
        }

        guard let change = try applyEnabledStates(
            to: [mod],
            install: install,
            fileManager: fileManager,
            shouldEnable: { _ in enabled }
        ).first else {
            return mod.url
        }
        return change.destinationURL
    }

    static func applyEnabledStates(
        to mods: [ModInfo],
        install: StardewInstall,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil,
        shouldEnable: (ModInfo) -> Bool
    ) throws -> [ModEnabledStateChange] {
        var changes: [ModEnabledStateChange] = []
        var operations: [FileMoveOperation] = []

        for mod in mods {
            let enabled = shouldEnable(mod)
            guard mod.isEnabled != enabled else {
                continue
            }

            let destinationURL = try enabledDestinationURL(
                for: mod,
                enabled: enabled,
                fileManager: fileManager
            )
            changes.append(
                ModEnabledStateChange(
                    mod: mod,
                    destinationURL: destinationURL
                )
            )
            operations.append(
                FileMoveOperation(
                    sourceURL: mod.url,
                    destinationURL: destinationURL
                )
            )
        }

        try FileMoveTransaction.perform(
            operations,
            context: install.fileMoveTransactionContext(),
            fileManager: fileManager,
            moveItem: moveItem
        )
        return changes
    }

    private static func enabledDestinationURL(
        for mod: ModInfo,
        enabled: Bool,
        fileManager: FileManager
    ) throws -> URL {
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

        return destinationURL
    }

    static func installMods(
        from sourceURLs: [URL],
        into install: StardewInstall,
        enabled: Bool = true,
        replacementPolicy: ModInstallReplacementPolicy = .newerOnly,
        archiveDirectory: URL? = nil,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) throws -> ModInstallResult {
        try ModInstallWorkflow.installMods(
            from: sourceURLs,
            into: install,
            enabled: enabled,
            replacementPolicy: replacementPolicy,
            archiveDirectory: archiveDirectory,
            fileManager: fileManager,
            moveItem: moveItem
        )
    }

    static func previewImport(
        from sourceURLs: [URL],
        into install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> ModImportPreview {
        try ModInstallWorkflow.previewImport(
            from: sourceURLs,
            into: install,
            fileManager: fileManager
        )
    }

    static func installPreview(
        _ preview: ModImportPreview,
        into install: StardewInstall,
        enabled: Bool = true,
        archiveDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> ModInstallResult {
        try ModInstallWorkflow.installPreview(
            preview,
            into: install,
            enabled: enabled,
            archiveDirectory: archiveDirectory,
            fileManager: fileManager
        )
    }

    static func discardImportPreview(
        _ preview: ModImportPreview,
        fileManager: FileManager = .default
    ) {
        ModInstallWorkflow.discardImportPreview(preview, fileManager: fileManager)
    }

    static func archive(
        _ mod: ModInfo,
        into install: StardewInstall,
        archiveDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        try ModArchive.archive(
            mod.url,
            into: install,
            archiveDirectory: archiveDirectory,
            reason: .deleted,
            fileManager: fileManager
        )
    }

    static func archive(
        _ mods: [ModInfo],
        into install: StardewInstall,
        archiveDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try ModArchive.archive(
            mods.map(\.url),
            into: install,
            archiveDirectory: archiveDirectory,
            reason: .deleted,
            fileManager: fileManager
        )
    }

    static func restoreArchivedMods(
        _ archivedMods: [ArchivedModInfo],
        into install: StardewInstall,
        archiveDirectory: URL? = nil,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) throws -> [RestoredModResult] {
        guard fileManager.directoryExists(at: install.modDirectoryURL) else {
            throw ModLibraryError.modFolderMissing(install.modDirectoryURL)
        }

        let resolvedArchiveDirectory = archiveDirectory ?? install.archivedModsDirectoryURL
        let transactionContext = install.fileMoveTransactionContext(
            archiveDirectory: resolvedArchiveDirectory
        )
        try FileMoveTransaction.recoverIfNeeded(
            context: transactionContext,
            fileManager: fileManager,
            moveItem: moveItem
        )
        let currentLocations = ModInstalledCatalog.locations(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )
        var claimedCurrentPaths: Set<String> = []
        var restorePlans: [(
            archivedMod: ArchivedModInfo,
            destinationURL: URL,
            currentURL: URL?
        )] = []

        for archivedMod in archivedMods {
            try validateArchivedModIsInsideArchive(
                archivedMod,
                archiveDirectory: resolvedArchiveDirectory
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
            )
            guard fileManager.directoryExists(at: archivedMod.url) else {
                throw ModLibraryError.modFolderMissing(archivedMod.url)
            }

            let matchingLocation = ModInstalledCatalog.matchingInstalledMod(
                normalizedUniqueID: archivedMod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
                destinationToken: archivedMod.enabledFolderName.normalizedFolderToken,
                installedMods: currentLocations
            )
            let destinationURL = matchingLocation?.url
                ?? install.modDirectoryURL.appendingPathComponent(archivedMod.folderName)

            if fileManager.fileExists(atPath: destinationURL.path),
               matchingLocation == nil {
                throw ModLibraryError.destinationExists(destinationURL)
            }
            if let matchingLocation,
               !claimedCurrentPaths.insert(matchingLocation.url.standardizedFileURL.path).inserted {
                throw ModLibraryError.destinationExists(matchingLocation.url)
            }

            restorePlans.append(
                (
                    archivedMod: archivedMod,
                    destinationURL: destinationURL,
                    currentURL: matchingLocation?.url
                )
            )
        }

        let currentURLs = restorePlans.compactMap { $0.currentURL }
        let currentArchivePlan = try currentURLs.isEmpty
            ? nil
            : ModArchive.prepareArchiveMoves(
                for: currentURLs,
                in: resolvedArchiveDirectory,
                reason: .updated,
                fileManager: fileManager
            )
        let archivedCurrentURLsBySourcePath = Dictionary(
            uniqueKeysWithValues: (currentArchivePlan?.operations ?? []).map {
                ($0.sourceURL.standardizedFileURL.path, $0.destinationURL)
            }
        )
        let restoreOperations = restorePlans.map {
            FileMoveOperation(
                sourceURL: $0.archivedMod.url,
                destinationURL: $0.destinationURL
            )
        }

        do {
            try FileMoveTransaction.perform(
                (currentArchivePlan?.operations ?? []) + restoreOperations,
                context: transactionContext,
                fileManager: fileManager,
                moveItem: moveItem
            )
        } catch {
            if let currentArchivePlan {
                ModArchive.removeContainerIfEmpty(
                    currentArchivePlan.containerURL,
                    fileManager: fileManager
                )
            }
            throw error
        }

        for plan in restorePlans {
            removeEmptyArchiveContainerIfNeeded(
                plan.archivedMod.containerURL,
                archiveDirectory: resolvedArchiveDirectory,
                fileManager: fileManager
            )
        }

        let results = restorePlans.map { plan in
            RestoredModResult(
                sourceURL: plan.archivedMod.url,
                destinationURL: plan.destinationURL,
                archivedCurrentURL: plan.currentURL.flatMap {
                    archivedCurrentURLsBySourcePath[$0.standardizedFileURL.path]
                },
                displayName: plan.archivedMod.displayName,
                version: plan.archivedMod.manifest?.version?.trimmedNonEmpty
            )
        }
        return results
    }

    @discardableResult
    static func deleteArchivedMods(
        _ archivedMods: [ArchivedModInfo],
        archiveDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> Int {
        var deletedCount = 0
        let resolvedArchiveDirectory = archiveDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()

        for archivedMod in archivedMods {
            try validateArchivedModIsInsideArchive(
                archivedMod,
                archiveDirectory: resolvedArchiveDirectory
            )

            guard fileManager.directoryExists(at: archivedMod.url) else {
                throw ModLibraryError.modFolderMissing(archivedMod.url)
            }

            try fileManager.removeItem(at: archivedMod.url)
            deletedCount += 1
            removeEmptyArchiveContainerIfNeeded(
                archivedMod.containerURL,
                archiveDirectory: archiveDirectory,
                fileManager: fileManager
            )
        }

        return deletedCount
    }

    private static func validateArchivedModIsInsideArchive(
        _ archivedMod: ArchivedModInfo,
        archiveDirectory: URL
    ) throws {
        let containerURL = archivedMod.containerURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let archivedModURL = archivedMod.url
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard containerURL.deletingLastPathComponent() == archiveDirectory,
              archivedModURL.deletingLastPathComponent() == containerURL
        else {
            throw ModLibraryError.archivedModOutsideArchive(archivedMod.url)
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
              // The metadata sidecar doesn't keep a container alive once its
              // last archived mod is restored.
              !children.contains(where: { fileManager.directoryExists(at: $0) })
        else {
            return
        }

        try? fileManager.removeItem(at: containerURL)
    }

}
