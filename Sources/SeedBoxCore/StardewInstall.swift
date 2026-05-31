import Foundation

public struct StardewInstall: Equatable {
    public static let modFolderName = "Mods-SVE"

    public var macOSDirectory: URL

    public init(macOSDirectory: URL) {
        self.macOSDirectory = macOSDirectory.standardizedFileURL
    }

    public var smapiExecutableURL: URL {
        macOSDirectory.appendingPathComponent("StardewModdingAPI")
    }

    public var modDirectoryURL: URL {
        macOSDirectory.appendingPathComponent(Self.modFolderName)
    }

    public var vanillaModDirectoryURL: URL {
        macOSDirectory.appendingPathComponent("Mods")
    }

    public var launchArguments: [String] {
        ["--mods-path", Self.modFolderName]
    }

    public func status(fileManager: FileManager = .default) -> InstallationStatus {
        let installDirectoryExists = fileManager.directoryExists(at: macOSDirectory)
        let smapiExecutableExists = fileManager.isExecutableFile(atPath: smapiExecutableURL.path)
        let modDirectoryExists = fileManager.directoryExists(at: modDirectoryURL)
        let vanillaModDirectoryExists = fileManager.directoryExists(at: vanillaModDirectoryURL)

        var issues: [InstallationIssue] = []
        if !installDirectoryExists {
            issues.append(.missingInstallDirectory(macOSDirectory))
        }
        if !smapiExecutableExists {
            issues.append(.missingSMAPI(smapiExecutableURL))
        }
        if !modDirectoryExists {
            issues.append(.missingModDirectory(modDirectoryURL))
        }

        return InstallationStatus(
            installDirectoryExists: installDirectoryExists,
            smapiExecutableExists: smapiExecutableExists,
            modDirectoryExists: modDirectoryExists,
            vanillaModDirectoryExists: vanillaModDirectoryExists,
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
    public var installDirectoryExists: Bool
    public var smapiExecutableExists: Bool
    public var modDirectoryExists: Bool
    public var vanillaModDirectoryExists: Bool
    public var issues: [InstallationIssue]

    public var canLaunch: Bool {
        issues.isEmpty
    }

    public var headline: String {
        canLaunch ? "Ready" : "Needs setup"
    }

    public var detail: String {
        issues.first?.message ?? "SMAPI will launch with Mods-SVE."
    }
}

public enum InstallationIssue: Equatable {
    case missingInstallDirectory(URL)
    case missingSMAPI(URL)
    case missingModDirectory(URL)

    public var message: String {
        switch self {
        case .missingInstallDirectory(let url):
            return "Stardew Valley was not found at \(url.path)."
        case .missingSMAPI(let url):
            return "SMAPI was not found at \(url.path)."
        case .missingModDirectory(let url):
            return "The mod folder does not exist at \(url.path)."
        }
    }
}

public enum LauncherError: Error, Equatable, LocalizedError {
    case missingInstallDirectory(URL)
    case missingSMAPI(URL)
    case missingModDirectory(URL)
    case missingVanillaModDirectory(URL)

    public var errorDescription: String? {
        switch self {
        case .missingInstallDirectory(let url):
            return "Stardew Valley was not found at \(url.path)."
        case .missingSMAPI(let url):
            return "SMAPI was not found at \(url.path)."
        case .missingModDirectory(let url):
            return "The mod folder does not exist at \(url.path)."
        case .missingVanillaModDirectory(let url):
            return "The default Mods folder was not found at \(url.path)."
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
