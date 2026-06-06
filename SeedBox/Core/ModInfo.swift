import Foundation

struct ModInfo: Identifiable, Equatable, Sendable {
    var id: String
    var folderName: String
    var url: URL
    var isEnabled: Bool
    var manifest: ModManifest?
    var missingRequiredDependencies: [ModDependencyResolution]
    var missingOptionalDependencies: [ModDependencyResolution]

    init(
        id: String? = nil,
        folderName: String,
        url: URL,
        isEnabled: Bool,
        manifest: ModManifest?,
        missingRequiredDependencies: [ModDependencyResolution] = [],
        missingOptionalDependencies: [ModDependencyResolution] = []
    ) {
        self.folderName = folderName
        self.url = url
        self.isEnabled = isEnabled
        self.manifest = manifest
        self.missingRequiredDependencies = missingRequiredDependencies
        self.missingOptionalDependencies = missingOptionalDependencies
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
        manifest?.version ?? AppStrings.Mods.unknownVersion
    }

    var authorText: String {
        manifest?.author ?? AppStrings.Mods.unknownAuthor
    }

    var descriptionText: String? {
        guard let description = manifest?.description?.trimmedNonEmpty else {
            return nil
        }

        return description.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var dependencyRequirements: [ModDependencyRequirement] {
        requiredDependencyRequirements + optionalDependencyRequirements
    }

    var requiredDependencyRequirements: [ModDependencyRequirement] {
        var requirements: [ModDependencyRequirement] = []

        if let contentPackFor = manifest?.contentPackFor?.uniqueID?.trimmedNonEmpty {
            requirements.append(
                ModDependencyRequirement(
                    uniqueID: contentPackFor,
                    minimumVersion: manifest?.contentPackFor?.minimumVersion?.trimmedNonEmpty,
                    kind: .contentPackFor
                )
            )
        }

        if let dependencies = manifest?.dependencies {
            requirements.append(contentsOf: dependencies.compactMap { dependency in
                guard dependency.isRequired != false else {
                    return nil
                }

                guard let uniqueID = dependency.uniqueID?.trimmedNonEmpty else {
                    return nil
                }

                return ModDependencyRequirement(
                    uniqueID: uniqueID,
                    minimumVersion: dependency.minimumVersion?.trimmedNonEmpty,
                    kind: .requiredDependency
                )
            })
        }

        return requirements.uniquedByNormalizedDependencyID()
    }

    var optionalDependencyRequirements: [ModDependencyRequirement] {
        guard let dependencies = manifest?.dependencies else {
            return []
        }

        return dependencies.compactMap { dependency in
            guard dependency.isRequired == false,
                  let uniqueID = dependency.uniqueID?.trimmedNonEmpty
            else {
                return nil
            }

            return ModDependencyRequirement(
                uniqueID: uniqueID,
                minimumVersion: dependency.minimumVersion?.trimmedNonEmpty,
                kind: .optionalDependency
            )
        }
        .uniquedByNormalizedDependencyID()
    }

    var requiredDependencyIDs: [String] {
        requiredDependencyRequirements.map(\.uniqueID)
    }

    var missingRequiredDependencyIDs: [String] {
        missingRequiredDependencies.map(\.requirement.uniqueID)
    }

    var missingOptionalDependencyIDs: [String] {
        missingOptionalDependencies.map(\.requirement.uniqueID)
    }

    var stateText: String {
        isEnabled ? AppStrings.Mods.enabled : AppStrings.Mods.disabled
    }

    var typeText: String {
        guard let manifest else {
            return AppStrings.Mods.unknown
        }

        if manifest.contentPackFor?.uniqueID?.caseInsensitiveCompare("Pathoschild.ContentPatcher") == .orderedSame {
            return AppStrings.Mods.contentPatcher
        }

        return AppStrings.Mods.smapi
    }

    var updateSourceText: String {
        let sites = updateKeySites
        guard !sites.isEmpty else {
            return AppStrings.Mods.notLinked
        }

        return sites.joined(separator: ", ")
    }

    var updateKeysText: String? {
        guard let updateKeys = manifest?.updateKeys, !updateKeys.isEmpty else {
            return nil
        }

        return updateKeys.joined(separator: ", ")
    }

    var updateKeySites: [String] {
        let sites = (manifest?.updateKeys ?? []).compactMap { key -> String? in
            guard let separatorIndex = key.firstIndex(of: ":") else {
                return nil
            }

            let site = String(key[..<separatorIndex]).trimmedNonEmpty
            guard let site else {
                return nil
            }

            switch site.lowercased() {
            case "nexus":
                return AppStrings.Mods.nexus
            case "github":
                return AppStrings.Mods.github
            case "curseforge":
                return AppStrings.Mods.curseForge
            case "moddrop":
                return AppStrings.Mods.modDrop
            default:
                return site
            }
        }

        var seen: Set<String> = []
        return sites.filter { site in
            guard !seen.contains(site) else {
                return false
            }
            seen.insert(site)
            return true
        }
    }

    var manifestMetadataText: String? {
        var segments: [String] = []

        if let contentPackFor = manifest?.contentPackFor?.uniqueID?.trimmedNonEmpty {
            segments.append(AppStrings.Mods.contentPackFor(contentPackFor))
        }

        if let dependencies = manifest?.dependencies, !dependencies.isEmpty {
            let requiredCount = dependencies.filter { $0.isRequired != false }.count
            let optionalCount = dependencies.filter { $0.isRequired == false }.count

            if requiredCount > 0 && optionalCount > 0 {
                segments.append(AppStrings.Mods.dependencyMetadata(
                    requiredCount: requiredCount,
                    optionalCount: optionalCount
                ))
            } else if requiredCount > 0 {
                segments.append(AppStrings.Mods.requiredDependencyMetadata(count: requiredCount))
            } else {
                segments.append(AppStrings.Mods.optionalDependencyMetadata(count: optionalCount))
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
        return AppStrings.Mods.missingRequiredDependencies(
            missingRequiredDependencies.map(\.summaryText).joined(separator: ", ")
        )
    }

    var hasMissingOptionalDependencies: Bool {
        !missingOptionalDependencyIDs.isEmpty
    }

    var missingOptionalDependenciesText: String? {
        guard hasMissingOptionalDependencies else {
            return nil
        }
        return AppStrings.Mods.missingOptionalDependencies(
            missingOptionalDependencies.map(\.summaryText).joined(separator: ", ")
        )
    }
}

private extension Array where Element == ModDependencyRequirement {
    func uniquedByNormalizedDependencyID() -> [ModDependencyRequirement] {
        var requirements: [ModDependencyRequirement] = []
        var indexesByID: [String: Int] = [:]

        for requirement in self {
            let normalizedID = requirement.normalizedUniqueID
            guard !normalizedID.isEmpty else {
                continue
            }

            guard let existingIndex = indexesByID[normalizedID] else {
                indexesByID[normalizedID] = requirements.count
                requirements.append(requirement)
                continue
            }

            let existingMinimumVersion = requirements[existingIndex].minimumVersion
            if existingMinimumVersion == nil
                || ModVersionComparator.compare(
                    requirement.minimumVersion ?? "",
                    to: existingMinimumVersion ?? ""
                ) == .orderedDescending {
                requirements[existingIndex].minimumVersion = requirement.minimumVersion
            }
        }

        return requirements
    }
}
