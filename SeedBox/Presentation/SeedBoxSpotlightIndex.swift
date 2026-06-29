import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Builds Core Spotlight items for Seed Box's local library and maps a result's
/// identifier back to an in-app route, so a Spotlight hit can deep-link into the
/// right view.
///
/// Only safe, user-meaningful metadata is indexed — names, authors, versions,
/// and type — never paths, bookmarks, configs, logs, or mod contents.
enum SeedBoxSpotlightIndex {
    static let domainIdentifier = "com.fahlsing.seedbox.library"

    private static let prefix = "seedbox"
    private enum Kind: String {
        case mod
        case modSet
        case userSmartModSet
    }

    static func searchableItems(
        mods: [ModInfo],
        modSets: [ModSet],
        userSmartModSets: [UserSmartModSet]
    ) -> [CSSearchableItem] {
        var items: [CSSearchableItem] = []

        for mod in mods {
            items.append(
                makeItem(
                    identifier: identifier(.mod, mod.id),
                    title: mod.displayName,
                    description: modDescription(mod),
                    keywords: [mod.manifest?.author, mod.manifest?.version, mod.enabledFolderName]
                )
            )
        }

        for set in modSets {
            items.append(
                makeItem(
                    identifier: identifier(.modSet, set.id),
                    title: set.name,
                    description: AppStrings.Spotlight.modSetDescription,
                    keywords: [set.name]
                )
            )
        }

        for smartSet in userSmartModSets {
            items.append(
                makeItem(
                    identifier: identifier(.userSmartModSet, smartSet.id),
                    title: smartSet.name,
                    description: AppStrings.Spotlight.smartModSetDescription,
                    keywords: [smartSet.name]
                )
            )
        }

        return items
    }

    /// Maps a Spotlight result identifier back to a route, or nil when it is not
    /// a recognizable Seed Box identifier.
    static func route(forSpotlightIdentifier identifier: String) -> SeedBoxRoute? {
        let parts = identifier.split(
            separator: ":",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        guard parts.count == 3, parts[0] == prefix, let kind = Kind(rawValue: String(parts[1])) else {
            return nil
        }

        let value = String(parts[2])
        guard !value.isEmpty else {
            return nil
        }

        switch kind {
        case .mod:
            return .mod(id: value)
        case .modSet:
            return .modSet(id: value)
        case .userSmartModSet:
            return .userSmartModSet(id: value)
        }
    }

    private static func identifier(_ kind: Kind, _ id: String) -> String {
        "\(prefix):\(kind.rawValue):\(id)"
    }

    private static func makeItem(
        identifier: String,
        title: String,
        description: String?,
        keywords: [String?]
    ) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = description
        let resolvedKeywords = keywords.compactMap { $0?.trimmedNonEmpty }
        if !resolvedKeywords.isEmpty {
            attributes.keywords = resolvedKeywords
        }

        return CSSearchableItem(
            uniqueIdentifier: identifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }

    private static func modDescription(_ mod: ModInfo) -> String {
        let parts = [mod.typeText, mod.manifest?.version.map(AppStrings.Spotlight.version)]
            .compactMap { $0?.trimmedNonEmpty }
        return parts.joined(separator: " • ")
    }
}
