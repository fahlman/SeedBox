import XCTest
@testable import SeedBox

/// Edge-case coverage for dependent (inheriting) Mod Sets, locking down the
/// resolution rules before the feature becomes user-facing.
final class ModSetInheritanceTests: SeedBoxTestCase {
    // MARK: - Chains

    func testResolvesThreeLevelChain() throws {
        let a = makeSet(id: "A", disabled: ["alpha"])
        let b = makeSet(id: "B", parent: "A", disabled: ["bravo"])
        let c = makeSet(id: "C", parent: "B", disabled: ["charlie"])

        let resolved = ModSetResolver.resolve(c, in: [a, b, c])

        XCTAssertEqual(resolved.disabledFolderTokens, ["alpha", "bravo", "charlie"])
        XCTAssertEqual(resolved.appliedAncestorIDs, ["A", "B"])
        XCTAssertTrue(resolved.isInherited)
        XCTAssertFalse(resolved.hasInheritanceCycle)
        XCTAssertFalse(resolved.hasMissingParent)
    }

    func testRootSetWithoutParentResolvesToOwnTokensOnly() throws {
        let a = makeSet(id: "A", disabled: ["alpha"])

        let resolved = ModSetResolver.resolve(a, in: [a])

        XCTAssertEqual(resolved.disabledFolderTokens, ["alpha"])
        XCTAssertEqual(resolved.appliedAncestorIDs, [])
        XCTAssertFalse(resolved.isInherited)
        XCTAssertEqual(resolved.inheritedDisabledTokens, [])
    }

    // MARK: - Child overrides

    func testChildReEnablesModDisabledByParent() throws {
        let parent = makeSet(id: "parent", disabled: ["alpha", "bravo"])
        let child = makeSet(id: "child", parent: "parent", enabled: ["alpha"])

        let resolved = ModSetResolver.resolve(child, in: [parent, child])

        // Child re-enables alpha but keeps the inherited bravo disable.
        XCTAssertEqual(resolved.disabledFolderTokens, ["bravo"])
        XCTAssertEqual(resolved.inheritedDisabledTokens, ["alpha", "bravo"])
    }

    func testChildDisablesModEnabledByParent() throws {
        let parent = makeSet(id: "parent", disabled: ["alpha"])
        let child = makeSet(id: "child", parent: "parent", disabled: ["bravo"])

        let resolved = ModSetResolver.resolve(child, in: [parent, child])

        XCTAssertEqual(resolved.disabledFolderTokens, ["alpha", "bravo"])
    }

    func testLeafChoiceWinsOverConflictingAncestors() throws {
        // A disables alpha, B re-enables it, C disables it again: leaf wins.
        let a = makeSet(id: "A", disabled: ["alpha"])
        let b = makeSet(id: "B", parent: "A", enabled: ["alpha"])
        let c = makeSet(id: "C", parent: "B", disabled: ["alpha"])

        XCTAssertEqual(
            ModSetResolver.resolve(c, in: [a, b, c]).disabledFolderTokens,
            ["alpha"]
        )
        // And with the leaf re-enabling instead, alpha ends up enabled.
        let cEnable = makeSet(id: "C", parent: "B", enabled: ["alpha"])
        XCTAssertEqual(
            ModSetResolver.resolve(cEnable, in: [a, b, cEnable]).disabledFolderTokens,
            []
        )
    }

    func testInheritedAndOverriddenStateFlagsPerMod() throws {
        let install = try makeInstall()
        try makeInstalledMod(name: "Alpha", in: install, folderName: "Alpha")
        try makeInstalledMod(name: "Bravo", in: install, folderName: "Bravo")
        try makeInstalledMod(name: "Charlie", in: install, folderName: "Charlie")
        let mods = try ModLibrary.scan(install: install)
        let modByFolder = Dictionary(uniqueKeysWithValues: mods.map { ($0.enabledFolderName, $0) })

        let parent = makeSet(id: "parent", disabled: ["Alpha", "Bravo"])
        let child = makeSet(id: "child", parent: "parent", enabled: ["Alpha"], disabled: ["Charlie"])
        let resolved = ModSetResolver.resolve(child, in: [parent, child])

        let bravo = try XCTUnwrap(modByFolder["Bravo"])
        XCTAssertFalse(resolved.isEnabled(bravo))
        XCTAssertTrue(resolved.isInheritedState(for: bravo))
        XCTAssertFalse(resolved.overridesInheritedState(for: bravo))

        let alpha = try XCTUnwrap(modByFolder["Alpha"])
        XCTAssertTrue(resolved.isEnabled(alpha))
        XCTAssertFalse(resolved.isInheritedState(for: alpha))
        XCTAssertTrue(resolved.overridesInheritedState(for: alpha))

        let charlie = try XCTUnwrap(modByFolder["Charlie"])
        XCTAssertFalse(resolved.isEnabled(charlie))
        XCTAssertFalse(resolved.isInheritedState(for: charlie))
    }

    // MARK: - Cycles

    func testTwoSetCycleIsBrokenAndFlagged() throws {
        let a = makeSet(id: "A", parent: "B", disabled: ["alpha"])
        let b = makeSet(id: "B", parent: "A", disabled: ["bravo"])

        let resolved = ModSetResolver.resolve(a, in: [a, b])

        // Each set is applied at most once; result stays finite and flagged.
        XCTAssertEqual(resolved.disabledFolderTokens, ["alpha", "bravo"])
        XCTAssertTrue(resolved.hasInheritanceCycle)
    }

    func testSelfParentTreatedAsCycleWithNoInheritance() throws {
        let a = makeSet(id: "A", parent: "A", disabled: ["alpha"])

        let resolved = ModSetResolver.resolve(a, in: [a])

        XCTAssertEqual(resolved.disabledFolderTokens, ["alpha"])
        XCTAssertEqual(resolved.appliedAncestorIDs, [])
        XCTAssertTrue(resolved.hasInheritanceCycle)
    }

    func testWouldCreateCycleDetectsDirectAndIndirectCycles() throws {
        let a = makeSet(id: "A")
        let b = makeSet(id: "B", parent: "A")
        let c = makeSet(id: "C", parent: "B")
        let sets = [a, b, c]

        // A set cannot parent itself.
        XCTAssertTrue(ModSetResolver.wouldCreateCycle(assigning: "A", to: "A", in: sets))
        // A cannot inherit from its own descendant C.
        XCTAssertTrue(ModSetResolver.wouldCreateCycle(assigning: "C", to: "A", in: sets))
        // C inheriting from A is fine (A is already an ancestor, no new cycle).
        XCTAssertFalse(ModSetResolver.wouldCreateCycle(assigning: "A", to: "C", in: sets))
        // Unknown proposed parent cannot create a cycle.
        XCTAssertFalse(ModSetResolver.wouldCreateCycle(assigning: "ghost", to: "A", in: sets))
    }

    // MARK: - Missing and deleted parents

    func testMissingParentEndsChainAndIsFlagged() throws {
        let child = makeSet(id: "child", parent: "ghost", disabled: ["alpha"])

        let resolved = ModSetResolver.resolve(child, in: [child])

        XCTAssertEqual(resolved.disabledFolderTokens, ["alpha"])
        XCTAssertTrue(resolved.hasMissingParent)
        XCTAssertEqual(resolved.appliedAncestorIDs, [])
    }

    func testDeletedParentLeavesChildResolvableFromOwnChoices() throws {
        let child = makeSet(id: "child", parent: "parent", disabled: ["bravo"])

        // Simulate the parent being deleted: it is absent from the known sets.
        let resolved = ModSetResolver.resolve(child, in: [child])

        XCTAssertEqual(resolved.disabledFolderTokens, ["bravo"])
        XCTAssertTrue(resolved.hasMissingParent)
    }

    func testSetsDirectlyInheritingFromParent() throws {
        let parent = makeSet(id: "parent")
        let childA = makeSet(id: "childA", parent: "parent")
        let childB = makeSet(id: "childB", parent: "parent")
        let grandchild = makeSet(id: "grandchild", parent: "childA")
        let unrelated = makeSet(id: "unrelated")

        let direct = ModSetResolver.sets(
            directlyInheritingFrom: "parent",
            in: [parent, childA, childB, grandchild, unrelated]
        )

        XCTAssertEqual(Set(direct.map(\.id)), ["childA", "childB"])
    }

    // MARK: - Renamed parents, duplicate names, stable IDs

    func testInheritanceFollowsParentIDNotName() throws {
        var parent = makeSet(id: "parent", disabled: ["alpha"])
        let child = makeSet(id: "child", parent: "parent", disabled: ["bravo"])

        let before = ModSetResolver.resolve(child, in: [parent, child])
        parent.name = "Renamed Parent"
        let after = ModSetResolver.resolve(child, in: [parent, child])

        XCTAssertEqual(before.disabledFolderTokens, after.disabledFolderTokens)
        XCTAssertEqual(after.disabledFolderTokens, ["alpha", "bravo"])
    }

    func testDuplicateParentNamesResolveByID() throws {
        let realParent = ModSet(id: "real", name: "Shared Name", disabledFolderNames: ["alpha"])
        let decoyParent = ModSet(id: "decoy", name: "Shared Name", disabledFolderNames: ["bravo"])
        let child = makeSet(id: "child", parent: "real", disabled: ["charlie"])

        let resolved = ModSetResolver.resolve(child, in: [realParent, decoyParent, child])

        XCTAssertEqual(resolved.disabledFolderTokens, ["alpha", "charlie"])
    }

    // MARK: - Built-in sets

    func testChildCanInheritFromBuiltInNoneSet() throws {
        let none = ModSet(
            id: ModSetStore.noneSetID,
            name: ModSetStore.noneSetName,
            disabledFolderNames: ["alpha", "bravo", "charlie"],
            isEditable: false
        )
        let child = makeSet(id: "child", parent: ModSetStore.noneSetID, enabled: ["alpha"])

        let resolved = ModSetResolver.resolve(child, in: [none, child])

        XCTAssertEqual(resolved.disabledFolderTokens, ["bravo", "charlie"])
        XCTAssertEqual(resolved.appliedAncestorIDs, [ModSetStore.noneSetID])
    }

    // MARK: - Separation from Smart Mod Sets

    func testParentPointingAtNonModSetIDIsTreatedAsMissing() throws {
        // Smart Mod Sets live in a separate store; a ModSet parentID that does
        // not match any known ModSet must not silently resolve against them.
        let child = makeSet(id: "child", parent: "smart-saved-search", disabled: ["alpha"])

        let resolved = ModSetResolver.resolve(child, in: [child])

        XCTAssertTrue(resolved.hasMissingParent)
        XCTAssertEqual(resolved.disabledFolderTokens, ["alpha"])
    }

    // MARK: - Persistence (issue #33)

    func testPersistsAndReloadsParentAndEnabledOverrides() throws {
        let install = try makeInstall()
        let parent = makeSet(id: "parent", disabled: ["Alpha", "Bravo"])
        let child = makeSet(id: "child", parent: "parent", enabled: ["Alpha"], disabled: ["Charlie"])

        try ModSetStore.saveSet(parent, install: install)
        try ModSetStore.saveSet(child, install: install)

        let reloaded = try ModSetStore.loadSets(install: install, currentMods: [])
        let reloadedChild = try XCTUnwrap(reloaded.first { $0.id == "child" })
        XCTAssertEqual(reloadedChild.parentID, "parent")
        XCTAssertEqual(reloadedChild.enabledFolderNames, ["Alpha"])
        XCTAssertEqual(reloadedChild.disabledFolderNames, ["Charlie"])

        let reloadedParent = try XCTUnwrap(reloaded.first { $0.id == "parent" })
        XCTAssertNil(reloadedParent.parentID)
        XCTAssertEqual(reloadedParent.enabledFolderNames, [])
    }

    func testRootSetOmitsEnabledFolderNamesKeyOnDisk() throws {
        let install = try makeInstall()
        let set = makeSet(id: "root", disabled: ["Alpha"])

        try ModSetStore.saveSet(set, install: install)

        let url = install.modSetDirectoryURL.appendingPathComponent("root.plist")
        let payload = try XCTUnwrap(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url),
                format: nil
            ) as? [String: Any]
        )
        XCTAssertNil(payload["enabledFolderNames"])
        XCTAssertNil(payload["parentID"])
    }

    // MARK: - Helpers

    private func makeSet(
        id: String,
        parent: String? = nil,
        enabled: [String] = [],
        disabled: [String] = []
    ) -> ModSet {
        ModSet(
            id: id,
            name: id,
            disabledFolderNames: disabled,
            parentID: parent,
            enabledFolderNames: enabled
        )
    }
}
