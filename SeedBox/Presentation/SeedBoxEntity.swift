import Foundation

/// One shared, system-facing identity for a Seed Box object.
///
/// This is the common vocabulary every macOS integration speaks — Spotlight,
/// App Shortcuts, the menu bar, Finder services, notifications — so a Mod Set
/// has a single identity everywhere instead of one per surface. It carries only
/// safe display metadata (never paths, configs, logs, or bookmarks) and maps to
/// a ``SeedBoxRoute``.
struct SeedBoxEntity: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case mod
        case modSet
        case builtInSmartModSet
        case userSmartModSet
        case destination
    }

    /// The system surfaces an entity is exposed through.
    struct Surfaces: OptionSet, Sendable {
        let rawValue: Int
        static let spotlight = Surfaces(rawValue: 1 << 0)
        static let shortcuts = Surfaces(rawValue: 1 << 1)
        static let menuBar = Surfaces(rawValue: 1 << 2)
    }

    var kind: Kind
    /// The object's natural identifier (mod/set id, smart-set raw value, or a
    /// fixed destination key). Combined with `kind` to form a namespaced,
    /// system-safe identifier.
    var rawIdentifier: String
    var title: String
    var subtitle: String?
    var symbolName: String
    var keywords: [String]
    var route: SeedBoxRoute
    var surfaces: Surfaces

    /// A stable, namespaced identifier safe to hand to system frameworks.
    var systemIdentifier: String {
        "\(SeedBoxEntity.identifierPrefix):\(kind.rawValue):\(rawIdentifier)"
    }

    var id: String { systemIdentifier }

    static let identifierPrefix = "seedbox"
}

/// Generates the shared entities from current app state and maps their system
/// identifiers back to routes. State-driven, with no business logic of its own —
/// it reuses the same titles/symbols/routes the app already defines.
enum SeedBoxEntityCatalog {
    static func entities(from state: ModManagerState) -> [SeedBoxEntity] {
        destinationEntities()
            + SmartModSet.allCases.map(builtInSmartEntity)
            + state.userSmartModSets.map(userSmartEntity)
            + state.modSets.map(modSetEntity)
            + state.mods.map(modEntity)
    }

    static func entities(
        from state: ModManagerState,
        on surface: SeedBoxEntity.Surfaces
    ) -> [SeedBoxEntity] {
        entities(from: state).filter { $0.surfaces.contains(surface) }
    }

    /// Maps a system identifier back to a route, or nil when it is not a
    /// recognizable Seed Box identifier. Whether the target still exists is the
    /// route dispatcher's concern (it returns `.unavailable` for stale ids).
    static func route(forSystemIdentifier identifier: String) -> SeedBoxRoute? {
        let parts = identifier.split(
            separator: ":",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        guard
            parts.count == 3,
            parts[0] == SeedBoxEntity.identifierPrefix,
            let kind = SeedBoxEntity.Kind(rawValue: String(parts[1]))
        else {
            return nil
        }

        let raw = String(parts[2])
        guard !raw.isEmpty else {
            return nil
        }

        switch kind {
        case .mod:
            return .mod(id: raw)
        case .modSet:
            return .modSet(id: raw)
        case .userSmartModSet:
            return .userSmartModSet(id: raw)
        case .builtInSmartModSet:
            return SmartModSet(rawValue: raw).map(SeedBoxRoute.smartModSet)
        case .destination:
            return destinationRoute(raw)
        }
    }

    // MARK: - Builders

    private static func modEntity(_ mod: ModInfo) -> SeedBoxEntity {
        SeedBoxEntity(
            kind: .mod,
            rawIdentifier: mod.id,
            title: mod.displayName,
            subtitle: modSubtitle(mod),
            symbolName: "puzzlepiece.extension",
            keywords: [mod.manifest?.author, mod.manifest?.version, mod.enabledFolderName]
                .compactMap { $0?.trimmedNonEmpty },
            route: .mod(id: mod.id),
            surfaces: [.spotlight, .menuBar]
        )
    }

    private static func modSetEntity(_ set: ModSet) -> SeedBoxEntity {
        SeedBoxEntity(
            kind: .modSet,
            rawIdentifier: set.id,
            title: set.name,
            subtitle: AppStrings.Spotlight.modSetDescription,
            symbolName: "folder",
            keywords: [set.name],
            route: .modSet(id: set.id),
            surfaces: [.spotlight, .shortcuts, .menuBar]
        )
    }

    private static func builtInSmartEntity(_ smartSet: SmartModSet) -> SeedBoxEntity {
        SeedBoxEntity(
            kind: .builtInSmartModSet,
            rawIdentifier: smartSet.rawValue,
            title: smartSet.title,
            subtitle: AppStrings.Spotlight.smartModSetDescription,
            symbolName: smartSet.systemImage,
            keywords: [smartSet.title],
            route: .smartModSet(smartSet),
            surfaces: [.spotlight, .menuBar]
        )
    }

    private static func userSmartEntity(_ smartSet: UserSmartModSet) -> SeedBoxEntity {
        SeedBoxEntity(
            kind: .userSmartModSet,
            rawIdentifier: smartSet.id,
            title: smartSet.name,
            subtitle: AppStrings.Spotlight.smartModSetDescription,
            symbolName: smartSet.systemImageName,
            keywords: [smartSet.name],
            route: .userSmartModSet(id: smartSet.id),
            surfaces: [.spotlight, .shortcuts, .menuBar]
        )
    }

    private static func destinationEntities() -> [SeedBoxEntity] {
        [
            destination("problems", AppStrings.Toolbar.problems, "exclamationmark.triangle", .problems),
            destination("activity", AppStrings.Toolbar.activity, "clock", .activity),
            destination("restoreHistory", AppStrings.RestoreHistory.title, "clock.arrow.circlepath", .restoreHistory)
        ]
    }

    private static func destination(
        _ rawIdentifier: String,
        _ title: String,
        _ symbolName: String,
        _ route: SeedBoxRoute
    ) -> SeedBoxEntity {
        SeedBoxEntity(
            kind: .destination,
            rawIdentifier: rawIdentifier,
            title: title,
            subtitle: nil,
            symbolName: symbolName,
            keywords: [title],
            route: route,
            surfaces: [.menuBar]
        )
    }

    private static func destinationRoute(_ rawIdentifier: String) -> SeedBoxRoute? {
        switch rawIdentifier {
        case "problems":
            return .problems
        case "activity":
            return .activity
        case "restoreHistory":
            return .restoreHistory
        default:
            return nil
        }
    }

    private static func modSubtitle(_ mod: ModInfo) -> String? {
        let parts = [mod.typeText, mod.manifest?.version.map(AppStrings.Spotlight.version)]
            .compactMap { $0?.trimmedNonEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
