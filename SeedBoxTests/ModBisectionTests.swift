import XCTest
@testable import SeedBox

final class ModBisectionTests: XCTestCase {
    func testStartRequiresAtLeastTwoMods() {
        XCTAssertNil(ModBisection.start(enabledTokens: []))
        XCTAssertNil(ModBisection.start(enabledTokens: ["alpha"]))
        XCTAssertNotNil(ModBisection.start(enabledTokens: ["alpha", "beta"]))
    }

    func testStartSplitsCandidatesInHalf() throws {
        let session = try XCTUnwrap(
            ModBisection.start(enabledTokens: ["delta", "alpha", "charlie", "bravo"])
        )

        XCTAssertEqual(session.candidateTokens, ["alpha", "bravo", "charlie", "delta"])
        XCTAssertEqual(session.testingTokens, ["alpha", "bravo"])
        XCTAssertEqual(session.step, 1)
    }

    func testNarrowingFollowsTheProblem() throws {
        let session = try XCTUnwrap(
            ModBisection.start(enabledTokens: ["alpha", "bravo", "charlie", "delta"])
        )

        guard case .continuing(let narrowed) = ModBisection.narrowed(session, problemOccurred: true) else {
            return XCTFail("Expected the search to continue.")
        }
        XCTAssertEqual(narrowed.candidateTokens, ["alpha", "bravo"])
        XCTAssertEqual(narrowed.testingTokens, ["alpha"])
        XCTAssertEqual(narrowed.step, 2)

        guard case .identified(let token) = ModBisection.narrowed(narrowed, problemOccurred: false) else {
            return XCTFail("Expected an identification.")
        }
        XCTAssertEqual(token, "bravo")
    }

    func testClearedWhenProblemGoneWithEverySuspectDisabled() throws {
        var session = try XCTUnwrap(ModBisection.start(enabledTokens: ["alpha", "bravo"]))
        session.testingTokens = ["alpha", "bravo"]

        XCTAssertEqual(ModBisection.narrowed(session, problemOccurred: false), .cleared)
    }

    func testNarrowedToGroupWhenSuspectsCannotBeSeparated() throws {
        var session = try XCTUnwrap(ModBisection.start(enabledTokens: ["framework", "pack"]))
        // Dependency closure forced both suspects into the same test.
        session.testingTokens = ["framework", "pack"]

        XCTAssertEqual(
            ModBisection.narrowed(session, problemOccurred: true),
            .narrowedTo(["framework", "pack"])
        )
    }
}

@MainActor
final class ModBisectionWorkflowTests: SeedBoxTestCase {
    func testFullSearchIdentifiesCulpritAndRestoresOtherMods() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let modNames = ["Alpha", "Bravo", "Charlie", "Delta"]
        for modName in modNames {
            let modURL = install.modDirectoryURL.appendingPathComponent(modName)
            try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
            try writeManifest(name: modName, to: modURL)
        }

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        await viewModel.startBisection()
        let session = try XCTUnwrap(viewModel.state.bisectionSession)
        XCTAssertEqual(session.testingTokens, ["alpha", "bravo"])
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Alpha": true, "Bravo": true, "Charlie": false, "Delta": false
        ])

        // Problem persists with only Alpha+Bravo: suspect those, test Alpha alone.
        await viewModel.recordBisectionResult(problemOccurred: true)
        XCTAssertEqual(viewModel.state.bisectionSession?.testingTokens, ["alpha"])
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Alpha": true, "Bravo": false, "Charlie": false, "Delta": false
        ])

        // Problem gone with Alpha alone: Bravo is the culprit.
        await viewModel.recordBisectionResult(problemOccurred: false)

        XCTAssertNil(viewModel.state.bisectionSession)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Alpha": true, "Bravo": false, "Charlie": true, "Delta": true
        ])
        XCTAssertTrue(viewModel.state.statusLineMessage.contains("Bravo"))
        let auditEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(auditEntry.action, .problemSearch)
        XCTAssertEqual(auditEntry.details["event"], "finished")
    }

    func testTestConfigurationsCarryRequiredDependencies() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()

        let packURL = install.modDirectoryURL.appendingPathComponent("APack")
        try FileManager.default.createDirectory(at: packURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "A Pack",
            to: packURL,
            uniqueID: "Test.APack",
            dependencies: [("Test.ZFramework", true)]
        )
        for modName in ["BMod", "CMod", "ZFramework"] {
            let modURL = install.modDirectoryURL.appendingPathComponent(modName)
            try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
            try writeManifest(name: modName, to: modURL, uniqueID: "Test.\(modName)")
        }

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        await viewModel.startBisection()

        let session = try XCTUnwrap(viewModel.state.bisectionSession)
        XCTAssertEqual(session.testingTokens, ["apack", "bmod", "zframework"])
        let enabledStates = modEnabledStates(in: viewModel.state.mods)
        XCTAssertEqual(enabledStates["ZFramework"], true, "The pack's framework must load with it.")
        XCTAssertEqual(enabledStates["CMod"], false)
    }

    func testCancelRestoresOriginalStates() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        for modName in ["Alpha", "Bravo", "Charlie"] {
            let modURL = install.modDirectoryURL.appendingPathComponent(modName)
            try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
            try writeManifest(name: modName, to: modURL)
        }

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        let charlie = try XCTUnwrap(viewModel.state.mods.first { $0.displayName == "Charlie" })
        await viewModel.setMod(charlie, enabled: false)

        await viewModel.startBisection()
        XCTAssertNotNil(viewModel.state.bisectionSession)

        await viewModel.cancelBisection()

        XCTAssertNil(viewModel.state.bisectionSession)
        XCTAssertEqual(modEnabledStates(in: viewModel.state.mods), [
            "Alpha": true, "Bravo": true, "Charlie": false
        ])
    }

    func testSessionSurvivesRelaunch() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        for modName in ["Alpha", "Bravo", "Charlie", "Delta"] {
            let modURL = install.modDirectoryURL.appendingPathComponent(modName)
            try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
            try writeManifest(name: modName, to: modURL)
        }

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.startBisection()
        let session = try XCTUnwrap(viewModel.state.bisectionSession)

        let relaunchedViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await relaunchedViewModel.refresh()

        XCTAssertEqual(relaunchedViewModel.state.bisectionSession, session)
    }
}
