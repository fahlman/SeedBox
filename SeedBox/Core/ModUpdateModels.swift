import Foundation

struct ModUpdateQuery: Equatable, Sendable {
    var uniqueID: String
    var installedVersion: String?
    var updateKeys: [String]
}

struct ModUpdateCheckResult: Equatable, Sendable {
    var uniqueID: String
    var suggestedVersion: String?
    var downloadURL: URL?
    /// The mod's main page, resolved from the API's extended metadata.
    var pageURL: URL?
}

struct ModAvailableUpdate: Identifiable, Equatable, Sendable {
    var id: String { modID }
    /// The mod's normalized unique ID.
    var modID: String
    var displayName: String
    var installedVersion: String?
    var latestVersion: String
    var downloadURL: URL?
}

protocol ModUpdateChecking: Sendable {
    func checkForUpdates(
        _ queries: [ModUpdateQuery],
        apiVersion: String?
    ) async throws -> [ModUpdateCheckResult]
}

enum SMAPIIdentifiers {
    /// The synthetic entry id the SMAPI web API recognizes for SMAPI itself.
    static let smapiModID = "Pathoschild.SMAPI"
    static let smapiUpdateKey = "GitHub:Pathoschild/SMAPI"
    static let smapiHomeURL = URL(string: "https://smapi.io")!

    /// SMAPI's bundled mods, installed inside the Mods folder. Their manifest
    /// versions always match the installed SMAPI version, which lets the
    /// SMAPI version be detected without reading outside the Mods folder.
    static let bundledModIDs: Set<String> = [
        "SMAPI.ConsoleCommands".normalizedDependencyID,
        "SMAPI.SaveBackup".normalizedDependencyID
    ]

    static func detectedSMAPIVersion(in mods: [ModInfo]) -> String? {
        mods.lazy
            .filter { mod in
                guard let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID else {
                    return false
                }
                return bundledModIDs.contains(uniqueID)
            }
            .compactMap { $0.manifest?.version?.trimmedNonEmpty }
            .first
    }
}
