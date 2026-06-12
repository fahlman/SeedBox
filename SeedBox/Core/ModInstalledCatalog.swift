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

    static func urlsByToken(for locations: [InstalledModLocation]) -> [String: URL] {
        var urlsByToken: [String: URL] = [:]
        for location in locations {
            let token = location.folderName.normalizedFolderToken
            guard !token.isEmpty, urlsByToken[token] == nil else {
                continue
            }

            urlsByToken[token] = location.url
        }

        return urlsByToken
    }

    /// Matches by manifest unique ID when one is available, falling back to
    /// the normalized destination folder name.
    static func matchingInstalledMod(
        normalizedUniqueID: String?,
        destinationToken: String,
        installedMods: [InstalledModLocation]
    ) -> InstalledModLocation? {
        if let normalizedUniqueID,
           let match = installedMods.first(where: { installedMod in
               installedMod.normalizedUniqueID == normalizedUniqueID
           }) {
            return match
        }

        return installedMods.first { installedMod in
            installedMod.folderName.normalizedFolderToken == destinationToken
        }
    }
}
