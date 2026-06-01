import Foundation

public struct StardewInstall: Equatable {
    public static let modFolderName = "Mods"

    public var macOSDirectory: URL

    public init(macOSDirectory: URL) {
        self.macOSDirectory = macOSDirectory.standardizedFileURL
    }

    public var modDirectoryURL: URL {
        macOSDirectory.appendingPathComponent(Self.modFolderName)
    }

    public func status(fileManager: FileManager = .default) -> InstallationStatus {
        let installDirectoryExists = fileManager.directoryExists(at: macOSDirectory)
        let modDirectoryExists = fileManager.directoryExists(at: modDirectoryURL)

        var issues: [InstallationIssue] = []
        if !installDirectoryExists {
            issues.append(.missingInstallDirectory(macOSDirectory))
        }
        if !modDirectoryExists {
            issues.append(.missingModDirectory(modDirectoryURL))
        }

        return InstallationStatus(
            installDirectoryExists: installDirectoryExists,
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
    public var installDirectoryExists: Bool
    public var modDirectoryExists: Bool
    public var issues: [InstallationIssue]

    public var canManageMods: Bool {
        issues.isEmpty
    }

    public var headline: String {
        canManageMods ? "Ready" : "Needs setup"
    }

    public var detail: String {
        issues.first?.message ?? "Seed Box manages the default SMAPI Mods folder."
    }
}

public enum InstallationIssue: Equatable {
    case missingInstallDirectory(URL)
    case missingModDirectory(URL)

    public var message: String {
        switch self {
        case .missingInstallDirectory(let url):
            return "Stardew Valley was not found at \(url.path)."
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
