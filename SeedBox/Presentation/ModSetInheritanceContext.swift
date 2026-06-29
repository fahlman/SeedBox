import Foundation

/// Whether a mod's state in the selected Mod Set is inherited from its base set
/// or has been changed locally in this set.
enum ModInheritanceState: Equatable, Sendable {
    case inherited
    case overridden
}

/// Precomputed inheritance context for the selected Mod Set, so per-mod lookups
/// in the table are cheap set operations rather than repeated chain resolution.
/// Present only when the selected set inherits from a known base set.
struct ModSetInheritanceContext: Equatable, Sendable {
    var baseSetName: String
    var parentDisabledTokens: Set<String>
    var ownDisabledTokens: Set<String>
    var ownEnabledTokens: Set<String>

    func state(for mod: ModInfo) -> ModInheritanceState {
        let token = mod.enabledFolderName.normalizedFolderToken
        if ownDisabledTokens.contains(token) || ownEnabledTokens.contains(token) {
            return .overridden
        }
        return .inherited
    }

    /// The enabled state this mod would have purely from the base set, used when
    /// reverting a local override back to the inherited value.
    func baseEnabled(for mod: ModInfo) -> Bool {
        !parentDisabledTokens.contains(mod.enabledFolderName.normalizedFolderToken)
    }
}
