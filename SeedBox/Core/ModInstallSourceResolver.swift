import Foundation
import ZIPFoundation

struct ModInstallSource {
    var candidates: [ModInstallCandidate]
    var temporaryExtractionDirectory: URL?
}

struct ModInstallCandidate {
    var sourceURL: URL
    var destinationFolderName: String
    var manifest: ModManifest?
}

struct ModArchiveExtractionLimits: Sendable {
    /// Generous ceilings for real mod archives that still stop decompression
    /// bombs long before they exhaust disk space.
    static let standard = ModArchiveExtractionLimits(
        maximumEntryCount: 20_000,
        maximumTotalUncompressedByteCount: 4 * 1024 * 1024 * 1024
    )

    var maximumEntryCount: Int
    var maximumTotalUncompressedByteCount: UInt64
}

enum ModArchiveExtractionError: Error, Equatable, LocalizedError, Sendable {
    case tooManyEntries(URL, limit: Int)
    case expandsTooLarge(URL, limitByteCount: UInt64)

    var errorDescription: String? {
        switch self {
        case .tooManyEntries(let url, let limit):
            return AppStrings.Errors.archiveHasTooManyFiles(url.lastPathComponent, limit: limit)
        case .expandsTooLarge(let url, let limitByteCount):
            return AppStrings.Errors.archiveExpandsTooLarge(
                url.lastPathComponent,
                limitText: ByteCountFormatter.string(
                    fromByteCount: Int64(clamping: limitByteCount),
                    countStyle: .file
                )
            )
        }
    }
}

enum ModInstallSourceResolver {
    private static let maximumInstallSearchDepth = 8

    static func resolve(
        from sourceURL: URL,
        limits: ModArchiveExtractionLimits = .standard,
        fileManager: FileManager = .default
    ) throws -> ModInstallSource {
        guard sourceURL.pathExtension.lowercased() == "zip" else {
            return ModInstallSource(
                candidates: installCandidates(from: sourceURL, fileManager: fileManager),
                temporaryExtractionDirectory: nil
            )
        }

        try validateArchiveWithinLimits(sourceURL, limits: limits)

        let extractionDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("SeedBoxZip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        do {
            try fileManager.unzipItem(at: sourceURL, to: extractionDirectory)
        } catch {
            try? fileManager.removeItem(at: extractionDirectory)
            throw error
        }

        return ModInstallSource(
            candidates: installCandidates(
                from: extractionDirectory,
                rootDestinationFolderName: sourceURL.deletingPathExtension().lastPathComponent,
                fileManager: fileManager
            ),
            temporaryExtractionDirectory: extractionDirectory
        )
    }

    private static func validateArchiveWithinLimits(
        _ archiveURL: URL,
        limits: ModArchiveExtractionLimits
    ) throws {
        let archive = try Archive(url: archiveURL, accessMode: .read)

        var entryCount = 0
        var totalUncompressedByteCount: UInt64 = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= limits.maximumEntryCount else {
                throw ModArchiveExtractionError.tooManyEntries(
                    archiveURL,
                    limit: limits.maximumEntryCount
                )
            }

            let (sum, didOverflow) = totalUncompressedByteCount
                .addingReportingOverflow(entry.uncompressedSize)
            totalUncompressedByteCount = didOverflow ? .max : sum
            guard totalUncompressedByteCount <= limits.maximumTotalUncompressedByteCount else {
                throw ModArchiveExtractionError.expandsTooLarge(
                    archiveURL,
                    limitByteCount: limits.maximumTotalUncompressedByteCount
                )
            }
        }
    }

    private static func installCandidates(
        from sourceURL: URL,
        rootDestinationFolderName: String? = nil,
        fileManager: FileManager
    ) -> [ModInstallCandidate] {
        guard fileManager.directoryExists(at: sourceURL) else {
            return []
        }

        if ModManifestReader.directoryContainsManifest(sourceURL, fileManager: fileManager) {
            return [
                ModInstallCandidate(
                    sourceURL: sourceURL,
                    destinationFolderName: rootDestinationFolderName ?? sourceURL.lastPathComponent,
                    manifest: ModManifestReader.loadManifest(
                        at: sourceURL.appendingPathComponent(ModManifestReader.fileName)
                    )
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
    ) -> [ModInstallCandidate] {
        guard remainingDepth > 0 else {
            return []
        }

        let children = directoryChildren(in: directoryURL, fileManager: fileManager)
        return children.flatMap { childURL -> [ModInstallCandidate] in
            guard fileManager.directoryExists(at: childURL),
                  !shouldSkipInstallSearchDirectory(childURL)
            else {
                return []
            }

            if ModManifestReader.directoryContainsManifest(childURL, fileManager: fileManager) {
                return [
                    ModInstallCandidate(
                        sourceURL: childURL,
                        destinationFolderName: childURL.lastPathComponent,
                        manifest: ModManifestReader.loadManifest(
                            at: childURL.appendingPathComponent(ModManifestReader.fileName)
                        )
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
}
