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

enum ModInstallSourceResolver {
    private static let maximumInstallSearchDepth = 8

    static func resolve(
        from sourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> ModInstallSource {
        guard sourceURL.pathExtension.lowercased() == "zip" else {
            return ModInstallSource(
                candidates: installCandidates(from: sourceURL, fileManager: fileManager),
                temporaryExtractionDirectory: nil
            )
        }

        let extractionDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("SeedBoxZip-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try fileManager.unzipItem(at: sourceURL, to: extractionDirectory)

        return ModInstallSource(
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
