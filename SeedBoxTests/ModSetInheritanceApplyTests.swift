import XCTest
@testable import SeedBox

/// Covers applying inheriting Mod Sets to the Mods folder, plus the dependency
/// preflight and comparison paths that must reason about the resolved state.
final class ModSetInheritanceApplyTests: SeedBoxTestCase {
    func testApplyResolvesInheritedDisablesAndOwnDisables() throws {
        let install = try makeInstall()
        try makeInstalledMod(name: "Framework", in: install, folderName: "Framework")
        try makeInstalledMod(name: "Addon", in: install, folderName: "Addon")
        try makeInstalledMod(name: "Extra", in: install, folderName: "Extra")

        let parent = ModSet(id: "parent", name: "Parent", disabledFolderNames: ["Framework"])
        let child = ModSet(
            id: "child",
            name: "Child",
            disabledFolderNames: ["Extra"],
            parentID: "parent"
        )

        _ = try ModSetStore.applySet(child, in: [parent, child], install: install)

        let states = enabledStatesByFolder(in: install)
        XCTAssertEqual(states["Framework"], false, "Inherited disable should apply.")
        XCTAssertEqual(states["Extra"], false, "Own disable should apply.")
        XCTAssertEqual(states["Addon"], true, "Untouched mod stays enabled.")
    }

    func testApplyHonorsChildReEnablingInheritedDisable() throws {
        let install = try makeInstall()
        try makeInstalledMod(name: "Framework", in: install, folderName: "Framework")
        try makeInstalledMod(name: "Extra", in: install, folderName: "Extra")

        let parent = ModSet(
            id: "parent",
            name: "Parent",
            disabledFolderNames: ["Framework", "Extra"]
        )
        let child = ModSet(
            id: "child",
            name: "Child",
            disabledFolderNames: [],
            parentID: "parent",
            enabledFolderNames: ["Framework"]
        )

        _ = try ModSetStore.applySet(child, in: [parent, child], install: install)

        let states = enabledStatesByFolder(in: install)
        XCTAssertEqual(states["Framework"], true, "Child re-enable overrides parent disable.")
        XCTAssertEqual(states["Extra"], false, "Inherited disable stays.")
    }

    func testDependencyPreflightUsesResolvedChain() throws {
        let install = try makeInstall()
        try makeInstalledMod(
            name: "Framework",
            in: install,
            folderName: "Framework",
            uniqueID: "Test.Framework"
        )
        try makeInstalledMod(
            name: "Addon",
            in: install,
            folderName: "Addon",
            uniqueID: "Test.Addon",
            dependencies: [(uniqueID: "Test.Framework", isRequired: true)]
        )
        let mods = try ModLibrary.scan(install: install)
        let graph = ModDependencyGraph(mods: mods)

        let parent = ModSet(id: "parent", name: "Parent", disabledFolderNames: ["Framework"])
        let child = ModSet(id: "child", name: "Child", disabledFolderNames: [], parentID: "parent")

        // Resolving against the chain disables Framework, leaving Addon's
        // required dependency unsatisfied.
        let chainIssues = graph.issues(applying: child, in: [parent, child])
        XCTAssertEqual(chainIssues.map(\.modName), ["Addon"])

        // Resolving the child in isolation ignores the inherited disable, so no
        // issue is detected — confirming the chain is what surfaces it.
        XCTAssertTrue(graph.issues(applying: child).isEmpty)
    }

    func testComparisonReflectsResolvedChain() throws {
        let install = try makeInstall()
        try makeInstalledMod(name: "Framework", in: install, folderName: "Framework")
        try makeInstalledMod(name: "Extra", in: install, folderName: "Extra")
        let mods = try ModLibrary.scan(install: install)

        let parent = ModSet(id: "parent", name: "Parent", disabledFolderNames: ["Framework"])
        let child = ModSet(id: "child", name: "Child", disabledFolderNames: [], parentID: "parent")

        let chainComparison = ModManagerInsights.comparison(
            for: child,
            currentMods: mods,
            in: [parent, child]
        )
        XCTAssertEqual(chainComparison.differences.map(\.mod.enabledFolderName), ["Framework"])
        XCTAssertEqual(chainComparison.differences.first?.change, .disable)

        // Without the chain the inherited disable is invisible.
        let isolatedComparison = ModManagerInsights.comparison(for: child, currentMods: mods)
        XCTAssertTrue(isolatedComparison.differences.isEmpty)
    }

    private func enabledStatesByFolder(in install: StardewInstall) -> [String: Bool] {
        let mods = (try? ModLibrary.scan(install: install)) ?? []
        return Dictionary(
            uniqueKeysWithValues: mods.map { ($0.enabledFolderName, $0.isEnabled) }
        )
    }
}
