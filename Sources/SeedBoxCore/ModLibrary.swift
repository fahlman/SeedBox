import Foundation

public struct ModInfo: Identifiable, Equatable {
    public var id: String { url.path }

    public var folderName: String
    public var url: URL
    public var isEnabled: Bool
    public var manifest: ModManifest?

    public var displayName: String {
        manifest?.name ?? enabledFolderName
    }

    public var enabledFolderName: String {
        folderName.trimmingPrefix(".")
    }

    public var versionText: String {
        manifest?.version ?? "Unknown version"
    }

    public var authorText: String {
        manifest?.author ?? "Unknown author"
    }
}

public struct ModManifest: Codable, Equatable {
    public var name: String?
    public var author: String?
    public var version: String?
    public var description: String?
    public var uniqueID: String?

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case author = "Author"
        case version = "Version"
        case description = "Description"
        case uniqueID = "UniqueID"
    }
}

public enum ModLibraryError: Error, Equatable, LocalizedError {
    case modFolderMissing(URL)
    case destinationExists(URL)
    case invalidDisabledName(String)
    case noInstallableMods(URL)

    public var errorDescription: String? {
        switch self {
        case .modFolderMissing(let url):
            return "The mod folder does not exist at \(url.path)."
        case .destinationExists(let url):
            return "A mod already exists at \(url.path)."
        case .invalidDisabledName(let name):
            return "The disabled folder name \(name) cannot be enabled safely."
        case .noInstallableMods(let url):
            return "No installable mod folders were found in \(url.path)."
        }
    }
}

public enum ModLibrary {
    public static func scan(
        install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> [ModInfo] {
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

        return folders
            .map { url in
                let manifestURL = findManifest(in: url, fileManager: fileManager)
                return ModInfo(
                    folderName: url.lastPathComponent,
                    url: url,
                    isEnabled: !url.lastPathComponent.hasPrefix("."),
                    manifest: manifestURL.flatMap { loadManifest(at: $0) }
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    public static func setEnabled(
        _ mod: ModInfo,
        enabled: Bool,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard mod.isEnabled != enabled else {
            return mod.url
        }

        let destinationName: String
        if enabled {
            destinationName = mod.folderName.trimmingPrefix(".")
            guard !destinationName.isEmpty else {
                throw ModLibraryError.invalidDisabledName(mod.folderName)
            }
        } else {
            destinationName = "." + mod.folderName.trimmingPrefix(".")
        }

        let destinationURL = mod.url
            .deletingLastPathComponent()
            .appendingPathComponent(destinationName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw ModLibraryError.destinationExists(destinationURL)
        }

        try fileManager.moveItem(at: mod.url, to: destinationURL)
        return destinationURL
    }

    public static func installMods(
        from sourceURLs: [URL],
        into install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard fileManager.directoryExists(at: install.modDirectoryURL) else {
            throw ModLibraryError.modFolderMissing(install.modDirectoryURL)
        }

        var installedURLs: [URL] = []

        for sourceURL in sourceURLs {
            let candidates = installCandidates(from: sourceURL, fileManager: fileManager)
            guard !candidates.isEmpty else {
                throw ModLibraryError.noInstallableMods(sourceURL)
            }

            for candidateURL in candidates {
                let destinationURL = install.modDirectoryURL
                    .appendingPathComponent(candidateURL.lastPathComponent)

                if fileManager.fileExists(atPath: destinationURL.path) {
                    throw ModLibraryError.destinationExists(destinationURL)
                }

                try fileManager.copyItem(at: candidateURL, to: destinationURL)
                installedURLs.append(destinationURL)
            }
        }

        return installedURLs
    }

    public static func trash(
        _ mod: ModInfo,
        fileManager: FileManager = .default
    ) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(
            at: mod.url,
            resultingItemURL: &resultingURL
        )
    }

    static func installCandidates(
        from sourceURL: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        if fileManager.fileExists(atPath: sourceURL.appendingPathComponent("manifest.json").path) {
            return [sourceURL]
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let modChildren = children.filter { childURL in
            fileManager.directoryExists(at: childURL)
                && findManifest(in: childURL, maximumDepth: 2, fileManager: fileManager) != nil
        }

        if !modChildren.isEmpty {
            return modChildren
        }

        if findManifest(in: sourceURL, maximumDepth: 2, fileManager: fileManager) != nil {
            return [sourceURL]
        }

        return []
    }

    private static func loadManifest(at url: URL) -> ModManifest? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(ModManifest.self, from: data)
    }

    private static func findManifest(
        in directoryURL: URL,
        maximumDepth: Int = 3,
        fileManager: FileManager = .default
    ) -> URL? {
        let directURL = directoryURL.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }

        guard maximumDepth > 0 else {
            return nil
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for childURL in children where fileManager.directoryExists(at: childURL) {
            if let foundURL = findManifest(
                in: childURL,
                maximumDepth: maximumDepth - 1,
                fileManager: fileManager
            ) {
                return foundURL
            }
        }

        return nil
    }
}

private extension String {
    func trimmingPrefix(_ prefix: Character) -> String {
        var value = self
        while value.first == prefix {
            value.removeFirst()
        }
        return value
    }
}
