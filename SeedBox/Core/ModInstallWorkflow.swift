import Foundation

enum ModInstallWorkflow {
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
                                replacementKind: ModInstallPlanner.replacementKind(
                                    candidate: candidate,
                                    existingMod: existingMod
                                )
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

    private enum PendingInstallOperation {
        case install(candidate: ModInstallCandidate, destinationURL: URL)
        case update(candidate: ModInstallCandidate, existingMod: InstalledModLocation, replacementKind: ModReplacementKind)
    }

    private enum CompletedInstallOperation {
        case installed(URL)
        case updated(destinationURL: URL, archivedURL: URL)
    }

    private enum ConfigPreservationOutcome: Equatable {
        case nothingToPreserve
        case preserved
        case failed
    }

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
}
