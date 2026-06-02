import Foundation

struct ModInfo: Identifiable, Equatable, Sendable {
    var id: String
    var folderName: String
    var url: URL
    var isEnabled: Bool
    var manifest: ModManifest?
    var missingRequiredDependencyIDs: [String]
    var missingOptionalDependencyIDs: [String]

    init(
        id: String? = nil,
        folderName: String,
        url: URL,
        isEnabled: Bool,
        manifest: ModManifest?,
        missingRequiredDependencyIDs: [String] = [],
        missingOptionalDependencyIDs: [String] = []
    ) {
        self.folderName = folderName
        self.url = url
        self.isEnabled = isEnabled
        self.manifest = manifest
        self.missingRequiredDependencyIDs = missingRequiredDependencyIDs
        self.missingOptionalDependencyIDs = missingOptionalDependencyIDs
        self.id = id ?? Self.stableID(folderName: folderName, url: url)
    }

    static func stableID(folderName: String, url: URL) -> String {
        let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
        let folderToken = folderName.normalizedFolderToken
        return "\(parentPath)#\(folderToken)"
    }

    var enabledFolderName: String {
        folderName.trimmingPrefix(Character("."))
    }

    var displayName: String {
        manifest?.name ?? enabledFolderName
    }

    var versionText: String {
        manifest?.version ?? "Unknown version"
    }

    var authorText: String {
        manifest?.author ?? "Unknown author"
    }

    var stateText: String {
        isEnabled ? "Enabled" : "Disabled"
    }

    var typeText: String {
        guard let manifest else {
            return "Unknown"
        }

        if manifest.contentPackFor?.uniqueID?.caseInsensitiveCompare("Pathoschild.ContentPatcher") == .orderedSame {
            return "Content Patcher"
        }

        return "SMAPI"
    }

    var manifestMetadataText: String? {
        var segments: [String] = []

        if let contentPackFor = manifest?.contentPackFor?.uniqueID?.trimmedNonEmpty {
            segments.append("For \(contentPackFor)")
        }

        if let dependencies = manifest?.dependencies, !dependencies.isEmpty {
            let requiredCount = dependencies.filter { $0.isRequired != false }.count
            let optionalCount = dependencies.filter { $0.isRequired == false }.count

            if requiredCount > 0 && optionalCount > 0 {
                segments.append("\(requiredCount) required + \(optionalCount) optional deps")
            } else if requiredCount > 0 {
                segments.append("\(requiredCount) required \(requiredCount == 1 ? "dep" : "deps")")
            } else {
                segments.append("\(optionalCount) optional \(optionalCount == 1 ? "dep" : "deps")")
            }
        }

        guard !segments.isEmpty else {
            return nil
        }

        return segments.joined(separator: " • ")
    }

    var hasMissingRequiredDependencies: Bool {
        !missingRequiredDependencyIDs.isEmpty
    }

    var missingRequiredDependenciesText: String? {
        guard hasMissingRequiredDependencies else {
            return nil
        }
        return "Missing required: \(missingRequiredDependencyIDs.joined(separator: ", "))"
    }

    var hasMissingOptionalDependencies: Bool {
        !missingOptionalDependencyIDs.isEmpty
    }

    var missingOptionalDependenciesText: String? {
        guard hasMissingOptionalDependencies else {
            return nil
        }
        return "Missing optional: \(missingOptionalDependencyIDs.joined(separator: ", "))"
    }
}
