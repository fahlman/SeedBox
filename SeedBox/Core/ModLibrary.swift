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
        var temporaryExtractionDirectories: [URL] = []
        defer {
            for temporaryExtractionDirectory in temporaryExtractionDirectories {
                try? fileManager.removeItem(at: temporaryExtractionDirectory)
            }
        }

        var classifier = ModInstallClassifier(
            install: install,
            enabled: enabled,
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
                switch try classifier.classify(candidate).resolution {
                case .duplicateInSelection(let pendingURL):
                    result.skipped.append(
                        ModInstallPlanner.skippedResult(
                            for: candidate,
                            existingURL: pendingURL,
                            reason: .duplicateInSelection
                        )
                    )
                case .alreadyInstalledSameSource(let existingMod):
                    result.skipped.append(
                        ModInstallPlanner.skippedResult(
                            for: candidate,
                            existingMod: existingMod,
                            reason: .alreadyInstalled
                        )
                    )
                case .existingDiffers(let existingMod):
                    if ModInstallPlanner.shouldReplace(
                        candidate: candidate,
                        existingMod: existingMod,
                        policy: replacementPolicy
                    ) {
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
                case .alreadyInstalledByFolderName(let existingURL):
                    result.skipped.append(
                        ModInstallPlanner.skippedResult(
                            for: candidate,
                            existingURL: existingURL,
                            reason: .alreadyInstalled
                        )
                    )
                case .install(let destinationURL):
                    pendingOperations.append(.install(candidate: candidate, destinationURL: destinationURL))
                }
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
                    let configOutcome = preserveUserConfig(
                        from: archivedURL,
                        to: existingMod.url,
                        fileManager: fileManager
                    )
                    result.updated.append(
                        UpdatedModResult(
                            sourceURL: candidate.sourceURL,
                            destinationURL: existingMod.url,
                            archivedURL: archivedURL,
                            displayName: ModInstallPlanner.displayName(for: candidate, fallback: existingMod.displayName),
                            previousVersion: existingMod.version,
                            installedVersion: candidate.manifest?.version?.trimmedNonEmpty,
                            replacementKind: replacementKind,
                            preservedConfig: configOutcome == .preserved,
                            configPreservationFailed: configOutcome == .failed
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
        var temporaryExtractionDirectories: [URL] = []
        // On success the extraction directories outlive this call: the preview
        // owns them until it is installed or discarded.
        var shouldRemoveTemporaryExtractionDirectories = true
        defer {
            if shouldRemoveTemporaryExtractionDirectories {
                for temporaryExtractionDirectory in temporaryExtractionDirectories {
                    try? fileManager.removeItem(at: temporaryExtractionDirectory)
                }
            }
        }

        var classifier = ModInstallClassifier(
            install: install,
            enabled: true,
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
                let classified = try classifier.classify(candidate)
                let action: ModImportPreviewAction
                let existingMod: InstalledModLocation?

                switch classified.resolution {
                case .duplicateInSelection:
                    existingMod = nil
                    action = .duplicateInSelection
                case .alreadyInstalledSameSource(let match):
                    existingMod = match
                    action = .alreadyInstalled
                case .existingDiffers(let match):
                    existingMod = match
                    action = ModInstallPlanner.previewAction(candidate: candidate, existingMod: match)
                case .alreadyInstalledByFolderName(let existingURL):
                    existingMod = InstalledModLocation(
                        url: existingURL,
                        folderName: existingURL.lastPathComponent,
                        manifest: nil
                    )
                    action = .alreadyInstalled
                case .install:
                    existingMod = nil
                    action = .install
                }

                items.append(
                    ModImportPreviewItem(
                        sourceURL: candidate.sourceURL,
                        displayName: ModInstallPlanner.displayName(for: candidate, fallback: existingMod?.displayName),
                        selectedVersion: candidate.manifest?.version?.trimmedNonEmpty,
                        existingVersion: existingMod?.version,
                        destinationFolderName: classified.destinationFolderName,
                        existingFolderName: existingMod?.folderName,
                        action: action,
                        typeText: ModInstallPlanner.typeText(for: candidate.manifest)
                    )
                )
            }
        }

        shouldRemoveTemporaryExtractionDirectories = false
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
                    normalizedUniqueID: archivedMod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
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

    enum ConfigPreservationOutcome: Equatable {
        /// The replaced copy had no config to carry.
        case nothingToPreserve
        case preserved
        /// A config existed but couldn't be carried; the caller must surface
        /// this so the user knows their settings reset (the archive still
        /// holds the original).
        case failed
    }

    /// SMAPI mods keep user settings in config.json, which a freshly
    /// downloaded copy doesn't include. After replacing a mod, the previous
    /// copy's config is carried forward (winning over any shipped defaults)
    /// so an update doesn't silently reset the user's settings. A failure
    /// must not fail the install, but it must not be silent either.
    private static func preserveUserConfig(
        from archivedModURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) -> ConfigPreservationOutcome {
        let configFileName = "config.json"
        let archivedConfigURL = archivedModURL.appendingPathComponent(configFileName)
        guard fileManager.fileExists(atPath: archivedConfigURL.path),
              !fileManager.directoryExists(at: archivedConfigURL)
        else {
            return .nothingToPreserve
        }

        // Stage the copy first so a failure can't destroy the shipped config:
        // the destination is only replaced after the user's config has been
        // copied successfully.
        let destinationConfigURL = destinationURL.appendingPathComponent(configFileName)
        let stagedConfigURL = destinationURL.appendingPathComponent(".seedbox-config-staging")
        try? fileManager.removeItem(at: stagedConfigURL)

        do {
            try fileManager.copyItem(at: archivedConfigURL, to: stagedConfigURL)
            if fileManager.fileExists(atPath: destinationConfigURL.path) {
                _ = try fileManager.replaceItemAt(destinationConfigURL, withItemAt: stagedConfigURL)
            } else {
                try fileManager.moveItem(at: stagedConfigURL, to: destinationConfigURL)
            }
            return .preserved
        } catch {
            try? fileManager.removeItem(at: stagedConfigURL)
            AppLog.scan.error("Carrying config.json forward failed for \(destinationURL.lastPathComponent): \(error)")
            return .failed
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
