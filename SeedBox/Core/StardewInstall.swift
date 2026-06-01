import Foundation

public struct StardewInstall: Equatable {
    public static let modFolderName = "Mods"

    public var modsDirectory: URL

    public init(modsDirectory: URL) {
        self.modsDirectory = modsDirectory.standardizedFileURL
    }

    public static func defaultModsDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Steam")
            .appendingPathComponent("steamapps")
            .appendingPathComponent("common")
            .appendingPathComponent("Stardew Valley")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(modFolderName)
    }

    public var modDirectoryURL: URL {
        modsDirectory
    }

    public func status(fileManager: FileManager = .default) -> InstallationStatus {
        let modDirectoryExists = fileManager.directoryExists(at: modDirectoryURL)

        var issues: [InstallationIssue] = []
        if !modDirectoryExists {
            issues.append(.missingModDirectory(modDirectoryURL))
        }

        return InstallationStatus(
            modDirectoryExists: modDirectoryExists,
            issues: issues
        )
    }

    public func createModDirectory(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: modDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

public struct InstallationStatus: Equatable {
    public var modDirectoryExists: Bool
    public var issues: [InstallationIssue]

    public var canManageMods: Bool {
        issues.isEmpty
    }

    public var headline: String {
        canManageMods ? "Ready" : "Needs setup"
    }

    public var detail: String {
        issues.first?.message ?? "Seed Box manages the default Mods folder."
    }
}

public enum InstallationIssue: Equatable {
    case missingModDirectory(URL)

    public var message: String {
        switch self {
        case .missingModDirectory(let url):
            return "The mod folder does not exist at \(url.path)."
        }
    }
}

extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
