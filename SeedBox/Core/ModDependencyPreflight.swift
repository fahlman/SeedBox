import Foundation

enum ModDependencyPreflight {
    static func requiredIssuesIfEnabled(
        _ mod: ModInfo,
        among mods: [ModInfo]
    ) -> [ModDependencyResolution] {
        ModDependencyGraph(mods: mods).requiredIssuesIfEnabled(mod)
    }

    static func missingRequiredDependencyIDsIfEnabled(
        _ mod: ModInfo,
        among mods: [ModInfo]
    ) -> [String] {
        requiredIssuesIfEnabled(mod, among: mods).map(\.requirement.uniqueID)
    }

    static func enabledDependentsIfDisabled(
        _ mod: ModInfo,
        among mods: [ModInfo]
    ) -> [ModInfo] {
        ModDependencyGraph(mods: mods).enabledDependentsIfDisabled(mod)
    }

    static func issues(
        applying set: ModSet,
        to mods: [ModInfo]
    ) -> [ModDependencyIssue] {
        ModDependencyGraph(mods: mods).issues(applying: set)
    }
}
