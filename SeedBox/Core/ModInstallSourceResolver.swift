import Foundation
import ZIPFoundation

struct ModInstallSource {
    var candidates: [ModInstallCandidate]
    var temporaryExtractionDirectory: URL?
    var resourceUsage: ModImportResourceUsage
}

struct ModInstallCandidate {
    var sourceURL: URL
    var destinationFolderName: String
    var manifest: ModManifest?
}

enum ModInstallSourceResolver {
    private static let maximumInstallSearchDepth = 8

    static func resolveAll(
        from sourceURLs: [URL],
        sourceLimits: ModArchiveExtractionLimits = .standard,
        selectionLimits: ModImportSelectionLimits = .standard,
        fileManager: FileManager = .default
    ) throws -> [ModInstallSource] {
        guard sourceURLs.count <= selectionLimits.maximumSourceCount else {
            throw ModArchiveExtractionError.tooManySources(
                limit: selectionLimits.maximumSourceCount
            )
        }

        ModImportSecurity.removeAbandonedExtractionDirectories(
            fileManager: fileManager
        )

        var resolvedSources: [ModInstallSource] = []
        var totalUsage = ModImportResourceUsage(entryCount: 0, totalByteCount: 0)
        var shouldRemoveExtractionDirectories = true
        defer {
            if shouldRemoveExtractionDirectories {
                for directoryURL in resolvedSources.compactMap(
                    \.temporaryExtractionDirectory
                ) {
                    try? fileManager.removeItem(at: directoryURL)
                }
            }
        }

        for sourceURL in sourceURLs {
            let resolvedSource = try resolveSource(
                from: sourceURL,
                limits: sourceLimits,
                fileManager: fileManager
            )
            resolvedSources.append(resolvedSource)
            totalUsage.add(resolvedSource.resourceUsage)

            guard totalUsage.entryCount <= selectionLimits.maximumEntryCount else {
                throw ModArchiveExtractionError.selectionHasTooManyEntries(
                    limit: selectionLimits.maximumEntryCount
                )
            }
            guard totalUsage.totalByteCount <= selectionLimits.maximumTotalByteCount else {
                throw ModArchiveExtractionError.selectionExpandsTooLarge(
                    limitByteCount: selectionLimits.maximumTotalByteCount
                )
            }
        }

        shouldRemoveExtractionDirectories = false
        return resolvedSources
    }

    static func resolve(
        from sourceURL: URL,
        limits: ModArchiveExtractionLimits = .standard,
        fileManager: FileManager = .default
    ) throws -> ModInstallSource {
        ModImportSecurity.removeAbandonedExtractionDirectories(
            fileManager: fileManager
        )
        return try resolveSource(
            from: sourceURL,
            limits: limits,
            fileManager: fileManager
        )
    }

    private static func resolveSource(
        from sourceURL: URL,
        limits: ModArchiveExtractionLimits,
        fileManager: FileManager
    ) throws -> ModInstallSource {
        guard sourceURL.pathExtension.lowercased() == "zip" else {
            guard fileManager.directoryExists(at: sourceURL) else {
                return ModInstallSource(
                    candidates: [],
                    temporaryExtractionDirectory: nil,
                    resourceUsage: ModImportResourceUsage(
                        entryCount: 0,
                        totalByteCount: 0
                    )
                )
            }

            let usage = try ModImportSecurity.validateImportTree(
                at: sourceURL,
                limits: limits,
                fileManager: fileManager
            )
            return ModInstallSource(
                candidates: try installCandidates(
                    from: sourceURL,
                    fileManager: fileManager
                ),
                temporaryExtractionDirectory: nil,
                resourceUsage: usage
            )
        }

        let declaredUsage = try ModImportSecurity.validateArchive(
            at: sourceURL,
            limits: limits
        )
        try ModImportSecurity.validateAvailableCapacity(
            for: declaredUsage.totalByteCount,
            sourceURL: sourceURL,
            destinationDirectoryURL: fileManager.temporaryDirectory,
            limits: limits
        )

        let temporaryExtractionDirectory = try SecureTemporaryWorkspace.create(
            in: fileManager.temporaryDirectory,
            prefix: ModImportSecurity.extractionDirectoryPrefix,
            markerFileName: ModImportSecurity.extractionMarkerFileName,
            fileManager: fileManager
        )
        let extractionDirectory = temporaryExtractionDirectory
            .appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(
            at: extractionDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        do {
            try fileManager.unzipItem(at: sourceURL, to: extractionDirectory)
            let actualUsage = try ModImportSecurity.validateImportTree(
                at: extractionDirectory,
                limits: limits,
                fileManager: fileManager
            )
            return ModInstallSource(
                candidates: try installCandidates(
                    from: extractionDirectory,
                    rootDestinationFolderName: sourceURL
                        .deletingPathExtension()
                        .lastPathComponent,
                    fileManager: fileManager
                ),
                temporaryExtractionDirectory: temporaryExtractionDirectory,
                resourceUsage: ModImportResourceUsage(
                    entryCount: max(declaredUsage.entryCount, actualUsage.entryCount),
                    totalByteCount: max(
                        declaredUsage.totalByteCount,
                        actualUsage.totalByteCount
                    )
                )
            )
        } catch {
            try? fileManager.removeItem(at: temporaryExtractionDirectory)
            throw error
        }
    }

    private static func installCandidates(
        from sourceURL: URL,
        rootDestinationFolderName: String? = nil,
        fileManager: FileManager
    ) throws -> [ModInstallCandidate] {
        guard fileManager.directoryExists(at: sourceURL) else {
            return []
        }

        if try directoryContainsSafeManifest(sourceURL, fileManager: fileManager) {
            return [
                ModInstallCandidate(
                    sourceURL: sourceURL,
                    destinationFolderName: rootDestinationFolderName
                        ?? sourceURL.lastPathComponent,
                    manifest: ModManifestReader.loadManifest(
                        at: sourceURL.appendingPathComponent(ModManifestReader.fileName)
                    )
                )
            ]
        }

        return try nestedInstallCandidates(
            in: sourceURL,
            remainingDepth: maximumInstallSearchDepth,
            fileManager: fileManager
        )
    }

    private static func nestedInstallCandidates(
        in directoryURL: URL,
        remainingDepth: Int,
        fileManager: FileManager
    ) throws -> [ModInstallCandidate] {
        guard remainingDepth > 0 else {
            return []
        }

        let children = try directoryChildren(in: directoryURL, fileManager: fileManager)
        return try children.flatMap { childURL -> [ModInstallCandidate] in
            let values = try childURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw ModArchiveExtractionError.symbolicLinkNotAllowed(childURL)
            }
            guard values.isDirectory == true,
                  !shouldSkipInstallSearchDirectory(childURL)
            else {
                return []
            }

            if try directoryContainsSafeManifest(childURL, fileManager: fileManager) {
                return [
                    ModInstallCandidate(
                        sourceURL: childURL,
                        destinationFolderName: childURL.lastPathComponent,
                        manifest: ModManifestReader.loadManifest(
                            at: childURL.appendingPathComponent(
                                ModManifestReader.fileName
                            )
                        )
                    )
                ]
            }

            return try nestedInstallCandidates(
                in: childURL,
                remainingDepth: remainingDepth - 1,
                fileManager: fileManager
            )
        }
    }

    private static func directoryContainsSafeManifest(
        _ directoryURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let manifestURL = directoryURL.appendingPathComponent(ModManifestReader.fileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return false
        }

        let values = try manifestURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isSymbolicLink != true else {
            throw ModArchiveExtractionError.symbolicLinkNotAllowed(manifestURL)
        }
        guard values.isRegularFile == true else {
            throw ModArchiveExtractionError.unsupportedFileType(manifestURL)
        }
        return true
    }

    private static func directoryChildren(
        in directoryURL: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        .sorted {
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
}
