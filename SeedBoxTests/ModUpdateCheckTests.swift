import XCTest
@testable import SeedBox

@MainActor
final class ModUpdateCheckTests: SeedBoxTestCase {
    func testCheckFindsUpdatesAndAuditsResult() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let checker = SpyModUpdateChecker(results: [
            ModUpdateCheckResult(
                uniqueID: "Test.ContentPatcher",
                suggestedVersion: "2.0.0",
                downloadURL: URL(string: "https://www.nexusmods.com/stardewvalley/mods/1915")
            ),
            ModUpdateCheckResult(
                uniqueID: "Test.SaveBackup",
                suggestedVersion: "3.1.0",
                downloadURL: nil
            )
        ])

        for modName in ["Content Patcher", "Save Backup"] {
            let modURL = install.modDirectoryURL
                .appendingPathComponent(modName.replacingOccurrences(of: " ", with: ""))
            try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
            try writeManifest(name: modName, to: modURL, version: "1.2.3")
        }

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            updateChecker: checker
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.setChecksForModUpdates(true)

        await viewModel.checkForModUpdates()

        XCTAssertEqual(checker.receivedQueries.count, 1)
        XCTAssertEqual(
            Set(checker.receivedQueries[0].map(\.uniqueID)),
            ["Test.ContentPatcher", "Test.SaveBackup"]
        )
        XCTAssertEqual(viewModel.state.availableUpdates.map(\.latestVersion), ["2.0.0", "3.1.0"])
        XCTAssertEqual(viewModel.state.statusLineMessage, "Updates are available for 2 mods.")

        let contentPatcher = try XCTUnwrap(
            viewModel.state.mods.first { $0.displayName == "Content Patcher" }
        )
        let update = try XCTUnwrap(viewModel.state.availableUpdate(for: contentPatcher))
        XCTAssertEqual(update.latestVersion, "2.0.0")
        XCTAssertEqual(update.installedVersion, "1.2.3")

        let auditEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(auditEntry.action, .modUpdatesChecked)
        XCTAssertEqual(auditEntry.details["update_count"], "2")
    }

    func testCheckIsRefusedWhileOptOutAndSendsNothing() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let checker = SpyModUpdateChecker(results: [])
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            updateChecker: checker
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        await viewModel.checkForModUpdates()

        XCTAssertTrue(checker.receivedQueries.isEmpty)
        XCTAssertTrue(viewModel.state.availableUpdates.isEmpty)
        XCTAssertEqual(
            viewModel.state.statusLineMessage,
            "Turn on update checks in Settings to check for mod updates."
        )
    }

    func testUpToDateModsProduceNoAvailableUpdates() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let checker = SpyModUpdateChecker(results: [
            ModUpdateCheckResult(
                uniqueID: "Test.ContentPatcher",
                suggestedVersion: "1.2.3",
                downloadURL: nil
            )
        ])
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL, version: "1.2.3")

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            updateChecker: checker
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.setChecksForModUpdates(true)

        await viewModel.checkForModUpdates()

        XCTAssertTrue(viewModel.state.availableUpdates.isEmpty)
        XCTAssertEqual(viewModel.state.statusLineMessage, "All mods are up to date.")
    }

    func testFailedCheckRecordsErrorStatus() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let checker = SpyModUpdateChecker(results: [], error: URLError(.notConnectedToInternet))
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            updateChecker: checker
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.setChecksForModUpdates(true)

        await viewModel.checkForModUpdates()

        XCTAssertEqual(viewModel.state.activityStatus?.severity, .error)
        XCTAssertTrue(viewModel.state.availableUpdates.isEmpty)
    }

    func testDisablingUpdateChecksClearsKnownUpdates() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let checker = SpyModUpdateChecker(results: [
            ModUpdateCheckResult(uniqueID: "Test.ContentPatcher", suggestedVersion: "9.0.0", downloadURL: nil)
        ])
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            updateChecker: checker
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.setChecksForModUpdates(true)
        await viewModel.checkForModUpdates()
        XCTAssertFalse(viewModel.state.availableUpdates.isEmpty)

        await viewModel.setChecksForModUpdates(false)

        XCTAssertTrue(viewModel.state.availableUpdates.isEmpty)
        XCTAssertFalse(ModManagerPreferences(defaults: defaults).checksForModUpdates)
    }

    func testDerivesSMAPIVersionFromBundledModAndReportsSMAPIUpdate() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let checker = SpyModUpdateChecker(results: [
            ModUpdateCheckResult(
                uniqueID: "Pathoschild.SMAPI",
                suggestedVersion: "4.5.0",
                downloadURL: nil
            )
        ])

        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Console Commands",
            to: consoleCommandsURL,
            version: "4.1.0",
            uniqueID: "SMAPI.ConsoleCommands"
        )

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            updateChecker: checker
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.setChecksForModUpdates(true)

        await viewModel.checkForModUpdates()

        XCTAssertEqual(viewModel.state.detectedSMAPIVersion, "4.1.0")
        XCTAssertEqual(checker.receivedAPIVersions, ["4.1.0"])

        let smapiQuery = try XCTUnwrap(
            checker.receivedQueries.first?.first { $0.uniqueID == "Pathoschild.SMAPI" }
        )
        XCTAssertEqual(smapiQuery.installedVersion, "4.1.0")
        XCTAssertEqual(smapiQuery.updateKeys, ["GitHub:Pathoschild/SMAPI"])

        let smapiUpdate = try XCTUnwrap(viewModel.state.smapiUpdate)
        XCTAssertEqual(smapiUpdate.latestVersion, "4.5.0")
        XCTAssertEqual(smapiUpdate.installedVersion, "4.1.0")
        XCTAssertEqual(smapiUpdate.downloadURL?.absoluteString, "https://smapi.io")
        XCTAssertEqual(
            viewModel.state.statusLineMessage,
            "All mods are up to date. SMAPI 4.5.0 is available."
        )
    }

    func testSkipsSMAPIQueryWhenNoBundledModIsInstalled() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let checker = SpyModUpdateChecker(results: [])
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            updateChecker: checker
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.setChecksForModUpdates(true)

        await viewModel.checkForModUpdates()

        XCTAssertNil(viewModel.state.detectedSMAPIVersion)
        XCTAssertEqual(checker.receivedAPIVersions, [nil])
        XCTAssertFalse(
            checker.receivedQueries.first?.contains { $0.uniqueID == "Pathoschild.SMAPI" } ?? true
        )
        XCTAssertNil(viewModel.state.smapiUpdate)
    }

    func testUpToDateSMAPIProducesNoSMAPIUpdate() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let checker = SpyModUpdateChecker(results: [
            ModUpdateCheckResult(
                uniqueID: "Pathoschild.SMAPI",
                suggestedVersion: "4.1.0",
                downloadURL: nil
            )
        ])

        let saveBackupURL = install.modDirectoryURL.appendingPathComponent("SaveBackup")
        try FileManager.default.createDirectory(at: saveBackupURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Save Backup",
            to: saveBackupURL,
            version: "4.1.0",
            uniqueID: "SMAPI.SaveBackup"
        )

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            updateChecker: checker
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.setChecksForModUpdates(true)

        await viewModel.checkForModUpdates()

        XCTAssertNil(viewModel.state.smapiUpdate)
        XCTAssertEqual(viewModel.state.statusLineMessage, "All mods are up to date.")
    }

    func testUpdateCheckResolvesMissingDependencyPages() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let checker = SpyModUpdateChecker(results: [
            ModUpdateCheckResult(
                uniqueID: "Pathoschild.ContentPatcher",
                suggestedVersion: nil,
                downloadURL: nil,
                pageURL: URL(string: "https://www.nexusmods.com/stardewvalley/mods/1915")
            )
        ])

        let packURL = install.modDirectoryURL.appendingPathComponent("ExamplePack")
        try FileManager.default.createDirectory(at: packURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Example Pack",
            to: packURL,
            uniqueID: "Test.ExamplePack",
            contentPackForUniqueID: "Pathoschild.ContentPatcher"
        )

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL,
            updateChecker: checker
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.setChecksForModUpdates(true)

        await viewModel.checkForModUpdates()

        let dependencyQuery = try XCTUnwrap(
            checker.receivedQueries.first?.first { $0.uniqueID == "Pathoschild.ContentPatcher" }
        )
        XCTAssertNil(dependencyQuery.installedVersion)
        XCTAssertTrue(dependencyQuery.updateKeys.isEmpty)
        XCTAssertEqual(
            viewModel.state.knownModPageURLs["pathoschild.contentpatcher"]?.absoluteString,
            "https://www.nexusmods.com/stardewvalley/mods/1915"
        )
    }

    func testSearchMatchesUpdatesAvailable() {
        let mod = ModInfo(
            folderName: "Alpha",
            url: URL(fileURLWithPath: "/tmp/Mods/Alpha", isDirectory: true),
            isEnabled: true,
            manifest: nil
        )
        let query = ModSearchQuery("updates:available")

        XCTAssertTrue(query.matches(mod, hasAvailableUpdate: true))
        XCTAssertFalse(query.matches(mod, hasAvailableUpdate: false))
    }

    func testClientDecodesResponseAndRejectsInsecureDownloadURLs() throws {
        let responseJSON = """
        [
            {
                "id": "Pathoschild.ContentPatcher",
                "suggestedUpdate": {
                    "version": "2.7.3",
                    "url": "https://www.nexusmods.com/stardewvalley/mods/1915"
                },
                "metadata": {
                    "main": {
                        "version": "2.7.3",
                        "url": "https://www.nexusmods.com/stardewvalley/mods/1915"
                    }
                },
                "errors": []
            },
            {
                "id": "Some.OtherMod",
                "suggestedUpdate": {
                    "version": "1.1.0",
                    "url": "http://insecure.example/mod"
                }
            },
            {
                "id": "Up.ToDateMod",
                "suggestedUpdate": null,
                "errors": ["ignored"]
            }
        ]
        """

        let results = try SMAPIModUpdateClient.decodeResults(from: Data(responseJSON.utf8))

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].suggestedVersion, "2.7.3")
        XCTAssertEqual(
            results[0].downloadURL?.absoluteString,
            "https://www.nexusmods.com/stardewvalley/mods/1915"
        )
        XCTAssertEqual(
            results[0].pageURL?.absoluteString,
            "https://www.nexusmods.com/stardewvalley/mods/1915"
        )
        XCTAssertEqual(results[1].suggestedVersion, "1.1.0")
        XCTAssertNil(results[1].downloadURL, "Non-HTTPS download URLs must be discarded.")
        XCTAssertNil(results[1].pageURL)
        XCTAssertNil(results[2].suggestedVersion)
    }
}

private final class SpyModUpdateChecker: ModUpdateChecking, @unchecked Sendable {
    private(set) var receivedQueries: [[ModUpdateQuery]] = []
    private(set) var receivedAPIVersions: [String?] = []
    private let results: [ModUpdateCheckResult]
    private let error: Error?

    init(results: [ModUpdateCheckResult], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func checkForUpdates(
        _ queries: [ModUpdateQuery],
        apiVersion: String?
    ) async throws -> [ModUpdateCheckResult] {
        receivedQueries.append(queries)
        receivedAPIVersions.append(apiVersion)
        if let error {
            throw error
        }
        return results
    }
}
