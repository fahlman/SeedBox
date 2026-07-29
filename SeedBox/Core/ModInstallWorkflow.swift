import Foundation

enum ModInstallWorkflow {
    static let installStagingDirectoryPrefix = ".seedbox-install-staging-"
    private static let installStagingMarkerFileName = ".seedbox-staging"

    static func installMods(
        from sourceURLs: [URL],
        into install: StardewInstall,
        enabled: Bool = true,
        replacementPolicy: ModInstallReplacementPolicy = .newerOnly,
        archiveDirectory: URL? = nil,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) throws -> ModInstallResult {
        guard fileManager.directoryExists(at: install.modDirectoryURL) else {
            throw ModLibraryError.modFolderMissing(install.modDirectoryURL)
        }

        let resolvedArchiveDirectory = archiveDirectory ?? install.archivedModsDirectoryURL
        try FileMoveTransaction.recoverIfNeeded(
            in: resolvedArchiveDirectory,
            fileManager: fileManager
        )
        try FileMoveTransaction.recoverIfNeeded(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )
        try removeAbandonedStagingDirectories(
            in: install.modDirectoryURL,
            fileManager: fileManager
        )

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

        guard !pendingOperations.isEmpty else {
            return result
        }

        let stagingDirectoryURL = install.modDirectoryURL.appendingPathComponent(
            "\(installStagingDirectoryPrefix)\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: stagingDirectoryURL,
            withIntermediateDirectories: false
        )
        try Data().write(
            to: stagingDirectoryURL.appendingPathComponent(
                installStagingMarkerFileName
            ),
            options: .atomic
        )
        defer {
            try? fileManager.removeItem(at: stagingDirectoryURL)
        }

        var stagedOperations: [StagedInstallOperation] = []
        for (index, pendingOperation) in pendingOperations.enumerated() {
            let candidate: ModInstallCandidate
            let destinationURL: URL
            let existingMod: InstalledModLocation?
            let replacementKind: ModReplacementKind?
            switch pendingOperation {
            case .install(let pendingCandidate, let pendingDestinationURL):
                candidate = pendingCandidate
                destinationURL = pendingDestinationURL
                existingMod = nil
                replacementKind = nil
            case .update(
                let pendingCandidate,
                let pendingExistingMod,
                let pendingReplacementKind
            ):
                candidate = pendingCandidate
                destinationURL = pendingExistingMod.url
                existingMod = pendingExistingMod
                replacementKind = pendingReplacementKind
            }

            let stagedURL = stagingDirectoryURL.appendingPathComponent(
                "\(index)-\(candidate.sourceURL.lastPathComponent)",
                isDirectory: true
            )
            try fileManager.copyItem(at: candidate.sourceURL, to: stagedURL)
            let configOutcome = existingMod.map {
                preserveUserConfig(
                    from: $0.url,
                    to: stagedURL,
                    fileManager: fileManager
                )
            } ?? .nothingToPreserve
            stagedOperations.append(
                StagedInstallOperation(
                    candidate: candidate,
                    stagedURL: stagedURL,
                    destinationURL: destinationURL,
                    existingMod: existingMod,
                    replacementKind: replacementKind,
                    configOutcome: configOutcome,
                    archivedURL: nil
                )
            )
        }

        let existingURLs = stagedOperations.compactMap { $0.existingMod?.url }
        let archivePlan = try existingURLs.isEmpty
            ? nil
            : ModArchive.prepareArchiveMoves(
                for: existingURLs,
                in: resolvedArchiveDirectory,
                reason: .updated,
                fileManager: fileManager
            )
        let archiveURLsBySourcePath = Dictionary(
            uniqueKeysWithValues: (archivePlan?.operations ?? []).map {
                ($0.sourceURL.standardizedFileURL.path, $0.destinationURL)
            }
        )
        for index in stagedOperations.indices {
            guard let existingURL = stagedOperations[index].existingMod?.url else {
                continue
            }
            guard let archivedURL = archiveURLsBySourcePath[existingURL.standardizedFileURL.path] else {
                throw CocoaError(.fileWriteUnknown)
            }
            stagedOperations[index].archivedURL = archivedURL
        }

        let installMoves = stagedOperations.map {
            FileMoveOperation(
                sourceURL: $0.stagedURL,
                destinationURL: $0.destinationURL
            )
        }
        do {
            try FileMoveTransaction.perform(
                (archivePlan?.operations ?? []) + installMoves,
                journalDirectoryURL: install.modDirectoryURL,
                fileManager: fileManager,
                moveItem: moveItem
            )
        } catch {
            if let archivePlan {
                ModArchive.removeContainerIfEmpty(
                    archivePlan.containerURL,
                    fileManager: fileManager
                )
            }
            throw error
        }

        for operation in stagedOperations {
            if let existingMod = operation.existingMod,
               let replacementKind = operation.replacementKind,
               let archivedURL = operation.archivedURL {
                result.updated.append(
                    UpdatedModResult(
                        sourceURL: operation.candidate.sourceURL,
                        destinationURL: operation.destinationURL,
                        archivedURL: archivedURL,
                        displayName: ModInstallPlanner.displayName(
                            for: operation.candidate,
                            fallback: existingMod.displayName
                        ),
                        previousVersion: existingMod.version,
                        installedVersion: operation.candidate.manifest?.version?.trimmedNonEmpty,
                        replacementKind: replacementKind,
                        preservedConfig: operation.configOutcome == .preserved,
                        configPreservationFailed: operation.configOutcome == .failed
                    )
                )
            } else {
                result.installed.append(
                    InstalledModResult(
                        sourceURL: operation.candidate.sourceURL,
                        destinationURL: operation.destinationURL,
                        displayName: ModInstallPlanner.displayName(for: operation.candidate),
                        version: operation.candidate.manifest?.version?.trimmedNonEmpty
                    )
                )
            }
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

    private enum ConfigPreservationOutcome: Equatable {
        case nothingToPreserve
        case preserved
        case failed
    }

    private struct StagedInstallOperation {
        var candidate: ModInstallCandidate
        var stagedURL: URL
        var destinationURL: URL
        var existingMod: InstalledModLocation?
        var replacementKind: ModReplacementKind?
        var configOutcome: ConfigPreservationOutcome
        var archivedURL: URL?
    }

    static func removeAbandonedStagingDirectories(
        in modsDirectoryURL: URL,
        fileManager: FileManager
    ) throws {
        let children = try fileManager.contentsOfDirectory(
            at: modsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for childURL in children
        where childURL.lastPathComponent.hasPrefix(installStagingDirectoryPrefix)
            && fileManager.directoryExists(at: childURL) {
            let markerURL = childURL.appendingPathComponent(
                installStagingMarkerFileName
            )
            let contents = try fileManager.contentsOfDirectory(
                at: childURL,
                includingPropertiesForKeys: nil
            )
            guard fileManager.fileExists(atPath: markerURL.path)
                    || contents.isEmpty
            else {
                continue
            }
            try fileManager.removeItem(at: childURL)
        }
    }

    private static func preserveUserConfig(
        from sourceModURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) -> ConfigPreservationOutcome {
        let configFileName = "config.json"
        let sourceConfigURL = sourceModURL.appendingPathComponent(configFileName)
        guard fileManager.fileExists(atPath: sourceConfigURL.path),
              !fileManager.directoryExists(at: sourceConfigURL)
        else {
            return .nothingToPreserve
        }

        let destinationConfigURL = destinationURL.appendingPathComponent(configFileName)
        let stagedConfigURL = destinationURL.appendingPathComponent(".seedbox-config-staging")
        try? fileManager.removeItem(at: stagedConfigURL)

        do {
            try fileManager.copyItem(at: sourceConfigURL, to: stagedConfigURL)
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
