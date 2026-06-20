import Foundation

struct ResolvedModSet: Equatable, Sendable {
    var set: ModSet
    var disabledFolderTokens: Set<String>

    func isEnabled(_ mod: ModInfo) -> Bool {
        !disabledFolderTokens.contains(mod.enabledFolderName.normalizedFolderToken)
    }
}

enum ModSetResolver {
    static func resolve(_ set: ModSet) -> ResolvedModSet {
        ResolvedModSet(
            set: set,
            disabledFolderTokens: set.disabledFolderTokens
        )
    }

    static func disabledFolderTokens(for set: ModSet) -> Set<String> {
        resolve(set).disabledFolderTokens
    }

    static func isEnabled(_ mod: ModInfo, applying set: ModSet) -> Bool {
        resolve(set).isEnabled(mod)
    }
}
