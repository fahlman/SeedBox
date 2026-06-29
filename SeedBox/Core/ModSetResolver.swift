import Foundation

struct ResolvedModSet: Equatable, Sendable {
    var set: ModSet
    var disabledFolderTokens: Set<String>

    /// Disabled tokens contributed purely by inherited ancestors, before this
    /// set's own choices were layered on top. Useful for distinguishing
    /// inherited state from this set's own overrides.
    var inheritedDisabledTokens: Set<String>

    /// Ancestor set IDs that were actually applied beneath this set, ordered
    /// root → nearest parent. Empty when the set has no usable parent.
    var appliedAncestorIDs: [String]

    /// True when the set declared a `parentID` that could not be found among
    /// the known sets (deleted or missing parent).
    var hasMissingParent: Bool

    /// True when following the parent chain encountered a cycle, which was
    /// broken so resolution stays finite and deterministic.
    var hasInheritanceCycle: Bool

    init(
        set: ModSet,
        disabledFolderTokens: Set<String>,
        inheritedDisabledTokens: Set<String> = [],
        appliedAncestorIDs: [String] = [],
        hasMissingParent: Bool = false,
        hasInheritanceCycle: Bool = false
    ) {
        self.set = set
        self.disabledFolderTokens = disabledFolderTokens
        self.inheritedDisabledTokens = inheritedDisabledTokens
        self.appliedAncestorIDs = appliedAncestorIDs
        self.hasMissingParent = hasMissingParent
        self.hasInheritanceCycle = hasInheritanceCycle
    }

    /// Whether this set actually inherited from one or more ancestors.
    var isInherited: Bool {
        !appliedAncestorIDs.isEmpty
    }

    func isEnabled(_ mod: ModInfo) -> Bool {
        !disabledFolderTokens.contains(mod.enabledFolderName.normalizedFolderToken)
    }

    /// Whether the given mod's resolved state came from an ancestor rather than
    /// this set's own choices.
    func isInheritedState(for mod: ModInfo) -> Bool {
        let token = mod.enabledFolderName.normalizedFolderToken
        let ownDisabled = set.disabledFolderTokens.contains(token)
        let ownEnabled = set.enabledFolderTokens.contains(token)
        return !ownDisabled && !ownEnabled && inheritedDisabledTokens.contains(token)
    }

    /// Whether this set explicitly overrode the inherited state for the mod
    /// (re-enabled something a parent disabled, or vice versa).
    func overridesInheritedState(for mod: ModInfo) -> Bool {
        let token = mod.enabledFolderName.normalizedFolderToken
        let inheritedDisabled = inheritedDisabledTokens.contains(token)
        let resolvedDisabled = disabledFolderTokens.contains(token)
        let touchedByOwnChoice = set.disabledFolderTokens.contains(token)
            || set.enabledFolderTokens.contains(token)
        return touchedByOwnChoice && inheritedDisabled != resolvedDisabled
    }
}

enum ModSetResolver {
    /// Resolves a single set in isolation, ignoring any declared parent.
    ///
    /// Used where a set's own choices are all that matter and no parent
    /// context is available. To resolve inheritance, use ``resolve(_:in:)``.
    static func resolve(_ set: ModSet) -> ResolvedModSet {
        ResolvedModSet(
            set: set,
            disabledFolderTokens: set.disabledFolderTokens
        )
    }

    /// Resolves a set against the full collection of known sets, applying its
    /// inheritance chain.
    ///
    /// Resolution walks from the set up through its ancestors, then applies
    /// each set's choices from root to leaf: tokens a set disables are added,
    /// tokens it explicitly enables are removed, so leaf-most choices win.
    ///
    /// - Cycles are broken: each set is applied at most once, and the result
    ///   is flagged via `hasInheritanceCycle`.
    /// - A `parentID` that is not present in `allSets` ends the chain and is
    ///   flagged via `hasMissingParent`.
    static func resolve(_ set: ModSet, in allSets: [ModSet]) -> ResolvedModSet {
        let resolvedChain = orderedChain(for: set, in: allSets)
        let chain = resolvedChain.chain

        var disabled: Set<String> = []
        var inheritedDisabled: Set<String> = []
        for (index, node) in chain.enumerated() {
            if index == chain.count - 1 {
                inheritedDisabled = disabled
            }
            disabled.formUnion(node.disabledFolderTokens)
            disabled.subtract(node.enabledFolderTokens)
        }

        return ResolvedModSet(
            set: set,
            disabledFolderTokens: disabled,
            inheritedDisabledTokens: inheritedDisabled,
            appliedAncestorIDs: chain.dropLast().map(\.id),
            hasMissingParent: resolvedChain.hasMissingParent,
            hasInheritanceCycle: resolvedChain.hasCycle
        )
    }

    /// The fully resolved disabled folder names for a set, canonicalized and
    /// sorted. Unlike the token set, this preserves human-readable folder names
    /// (preferring leaf-most), which the export format needs.
    static func resolvedDisabledFolderNames(for set: ModSet, in allSets: [ModSet]) -> [String] {
        let chain = orderedChain(for: set, in: allSets).chain

        // token -> canonical name, plus whether the token is currently disabled.
        var nameByToken: [String: String] = [:]
        var disabledTokens: Set<String> = []
        for node in chain {
            for name in node.disabledFolderNames {
                let canonical = name.trimmingPrefix(Character("."))
                let token = canonical.normalizedFolderToken
                guard !token.isEmpty else { continue }
                nameByToken[token] = canonical
                disabledTokens.insert(token)
            }
            for name in node.enabledFolderNames {
                let token = name.normalizedFolderToken
                disabledTokens.remove(token)
            }
        }

        return disabledTokens
            .compactMap { nameByToken[$0] }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Walks a set's parent chain, returning the sets ordered root → leaf with
    /// cycles broken and a missing parent flagged. Each set appears at most once.
    private static func orderedChain(
        for set: ModSet,
        in allSets: [ModSet]
    ) -> (chain: [ModSet], hasMissingParent: Bool, hasCycle: Bool) {
        let lookup = Dictionary(
            allSets.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )

        var chain: [ModSet] = []
        var visited: Set<String> = []
        var hasMissingParent = false
        var hasCycle = false

        var current: ModSet? = lookup[set.id] ?? set
        while let node = current {
            if visited.contains(node.id) {
                hasCycle = true
                break
            }
            visited.insert(node.id)
            chain.append(node)

            guard let parentID = node.parentID else {
                break
            }
            guard let parent = lookup[parentID] else {
                hasMissingParent = true
                break
            }
            current = parent
        }

        // chain is leaf → root; reverse so root choices apply first.
        chain.reverse()
        return (chain, hasMissingParent, hasCycle)
    }

    static func disabledFolderTokens(for set: ModSet) -> Set<String> {
        resolve(set).disabledFolderTokens
    }

    static func disabledFolderTokens(for set: ModSet, in allSets: [ModSet]) -> Set<String> {
        resolve(set, in: allSets).disabledFolderTokens
    }

    static func isEnabled(_ mod: ModInfo, applying set: ModSet) -> Bool {
        resolve(set).isEnabled(mod)
    }

    static func isEnabled(_ mod: ModInfo, applying set: ModSet, in allSets: [ModSet]) -> Bool {
        resolve(set, in: allSets).isEnabled(mod)
    }

    /// The ancestor chain for a set, ordered nearest parent → root.
    ///
    /// Stops at a missing parent and breaks cycles, so the returned IDs are
    /// always finite and free of repeats.
    static func ancestorIDs(of set: ModSet, in allSets: [ModSet]) -> [String] {
        let lookup = Dictionary(
            allSets.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )

        var ancestors: [String] = []
        var visited: Set<String> = [set.id]
        var parentID = set.parentID
        while let id = parentID, let parent = lookup[id], !visited.contains(id) {
            ancestors.append(id)
            visited.insert(id)
            parentID = parent.parentID
        }
        return ancestors
    }

    /// Whether assigning `parentID` to the set identified by `childID` would
    /// create an inheritance cycle.
    ///
    /// A set may not inherit from itself or from any of its own descendants.
    static func wouldCreateCycle(
        assigning parentID: String,
        to childID: String,
        in allSets: [ModSet]
    ) -> Bool {
        if parentID == childID {
            return true
        }
        guard let proposedParent = allSets.first(where: { $0.id == parentID }) else {
            return false
        }
        // The assignment is a cycle iff the child is already an ancestor of the
        // proposed parent.
        return ancestorIDs(of: proposedParent, in: allSets).contains(childID)
    }

    /// The sets that directly declare `parentID` as their parent.
    ///
    /// Useful when a parent is deleted, so callers can decide how to handle the
    /// now-orphaned children (see missing-parent behavior).
    static func sets(directlyInheritingFrom parentID: String, in allSets: [ModSet]) -> [ModSet] {
        allSets.filter { $0.parentID == parentID }
    }
}
