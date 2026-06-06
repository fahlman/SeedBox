import Foundation

struct InstalledModLocation: Equatable {
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

enum ModInstalledCatalog {
    static func locations(
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
                    manifest: ModManifestReader.findManifest(in: installedURL, fileManager: fileManager)
                        .flatMap { ModManifestReader.loadManifest(at: $0) }
                )
            }
    }

    static func urlsByToken(
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

    static func matchingInstalledMod(
        for candidate: ModInstallCandidate,
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

    static func matchingInstalledMod(
        for archivedMod: ArchivedModInfo,
        destinationToken: String,
        installedMods: [InstalledModLocation]
    ) -> InstalledModLocation? {
        if let archivedUniqueID = archivedMod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
           let match = installedMods.first(where: { installedMod in
               installedMod.normalizedUniqueID == archivedUniqueID
           }) {
            return match
        }

        return installedMods.first { installedMod in
            installedMod.folderName.normalizedFolderToken == destinationToken
        }
    }
}
