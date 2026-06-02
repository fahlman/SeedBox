import Foundation

public struct StardewInstall: Equatable {
    public static let modFolderName = "Mods"
    public static let modSetFolderName = "Mod Sets"
    public static let applicationSupportFolderName = "Seed Box"

    public var modsDirectory: URL
    public var modSetDirectory: URL

    public init(
        modsDirectory: URL,
        modSetDirectory: URL = Self.defaultModSetDirectory()
    ) {
        self.modsDirectory = modsDirectory.standardizedFileURL
        self.modSetDirectory = modSetDirectory.standardizedFileURL
    }

    public static func defaultModSetDirectory(
        applicationSupportDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
            .appendingPathComponent(modSetFolderName, isDirectory: true)
    }

    public static func knownDefaultModsDirectories(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> [URL] {
        let steamModsDirectory = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Steam")
            .appendingPathComponent("steamapps")
            .appendingPathComponent("common")
            .appendingPathComponent("Stardew Valley")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(modFolderName)

        let gogModsDirectory = applicationsDirectory
            .appendingPathComponent("Stardew Valley.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(modFolderName)

        return [steamModsDirectory, gogModsDirectory]
    }

    public static func hasAnyKnownDefaultModsDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager: FileManager = .default
    ) -> Bool {
        knownDefaultModsDirectories(
            homeDirectory: homeDirectory,
            applicationsDirectory: applicationsDirectory
        ).contains { candidate in
            fileManager.directoryExists(at: candidate)
        }
    }

    public static func defaultModsDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager: FileManager = .default
    ) -> URL {
        let candidates = knownDefaultModsDirectories(
            homeDirectory: homeDirectory,
            applicationsDirectory: applicationsDirectory
        )

        if let existingModsDirectory = candidates.first(where: { candidate in
            fileManager.directoryExists(at: candidate)
        }) {
            return existingModsDirectory
        }

        return candidates.first { candidate in
            fileManager.directoryExists(at: candidate.deletingLastPathComponent())
        } ?? candidates[0]
    }

    public var modDirectoryURL: URL {
        modsDirectory
    }

    public var modSetDirectoryURL: URL {
        modSetDirectory
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
