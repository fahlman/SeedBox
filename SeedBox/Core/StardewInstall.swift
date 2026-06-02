import Foundation

struct StardewInstall: Equatable, Sendable {
    static let modFolderName = "Mods"
    static let modSetFolderName = "Mod Sets"
    static let auditLogFileName = "Audit Log.plist"
    static let applicationSupportFolderName = "Seed Box"

    var modsDirectory: URL
    var modSetDirectory: URL

    init(
        modsDirectory: URL,
        modSetDirectory: URL = Self.defaultModSetDirectory()
    ) {
        self.modsDirectory = modsDirectory.standardizedFileURL
        self.modSetDirectory = modSetDirectory.standardizedFileURL
    }

    static func defaultModSetDirectory(
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

    static func defaultAuditLogURL(
        applicationSupportDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
            .appendingPathComponent(auditLogFileName)
    }

    static func auditLogURL(forModSetDirectory modSetDirectory: URL) -> URL {
        modSetDirectory
            .standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(auditLogFileName)
    }

    static func knownDefaultModsDirectories(
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

    static func hasAnyKnownDefaultModsDirectory(
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

    static func defaultModsDirectory(
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

    var modDirectoryURL: URL {
        modsDirectory
    }

    var modSetDirectoryURL: URL {
        modSetDirectory
    }

    var auditLogURL: URL {
        Self.auditLogURL(forModSetDirectory: modSetDirectory)
    }

    func status(fileManager: FileManager = .default) -> InstallationStatus {
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

    func createModDirectory(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: modDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

struct InstallationStatus: Equatable, Sendable {
    var modDirectoryExists: Bool
    var issues: [InstallationIssue]

    var canManageMods: Bool {
        issues.isEmpty
    }

    var headline: String {
        canManageMods ? "Ready" : "Needs setup"
    }

    var detail: String {
        issues.first?.message ?? "Seed Box manages the default Mods folder."
    }
}

enum InstallationIssue: Equatable, Sendable {
    case missingModDirectory(URL)

    var message: String {
        switch self {
        case .missingModDirectory(let url):
            return "The mod folder does not exist at \(url.path)."
        }
    }
}
