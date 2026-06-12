import XCTest
@testable import SeedBox

final class SMAPILogReaderTests: XCTestCase {
    private let fixtureLog = """
    [12:00:00 INFO  SMAPI] SMAPI 4.1.10 with Stardew Valley 1.6.15 (build 24356) on macOS
    [12:00:01 DEBUG SMAPI] Mods go here: /path/Mods
    [12:00:02 INFO  SMAPI] Loading mods...
    [12:00:03 DEBUG SMAPI]    Loaded 2 mods:
    [12:00:03 DEBUG SMAPI]       Fine Mod 1.2.3 by Author | does things
    [12:00:04 ERROR SMAPI]    Skipped mods
    [12:00:04 ERROR SMAPI]    --------------------------------------------------
    [12:00:04 ERROR SMAPI]       These mods could not be added to your game.
    [12:00:04 ERROR SMAPI]       - Broken Mod 1.0.0 because it's no longer compatible. Please check for a new version at https://smapi.io/mods.
    [12:00:04 ERROR SMAPI]       - Ghost Mod because its DLL is missing.
    [12:00:10 ERROR Fine Mod] Something failed
       at StackFrame.continuation()
       at AnotherFrame.continuation()
    [12:00:11 ERROR Fine Mod] Something failed again
    [12:00:12 ERROR game] game-level error is not attributed to a mod
    not a log line at all
    """

    func testParsesVersionsSkippedModsAndErrorCounts() {
        let report = SMAPILogReader.parse(fixtureLog)

        XCTAssertEqual(report.smapiVersion, "4.1.10")
        XCTAssertEqual(report.gameVersion, "1.6.15")

        XCTAssertEqual(report.skippedMods.count, 2)
        XCTAssertEqual(report.skippedMods.first?.name, "Broken Mod")
        XCTAssertEqual(report.skippedMods.first?.version, "1.0.0")
        XCTAssertEqual(
            report.skippedMods.first?.reason,
            "it's no longer compatible. Please check for a new version at https://smapi.io/mods."
        )
        XCTAssertEqual(report.skippedMods.last?.name, "Ghost Mod")
        XCTAssertNil(report.skippedMods.last?.version)
        XCTAssertEqual(report.skippedMods.last?.reason, "its DLL is missing.")

        XCTAssertEqual(report.modErrorCounts, ["fine mod": 2], "Continuation and game lines don't count.")
    }

    func testParsingGarbageProducesEmptyReport() {
        let report = SMAPILogReader.parse("complete nonsense\nwith no log lines\n")

        XCTAssertNil(report.smapiVersion)
        XCTAssertTrue(report.skippedMods.isEmpty)
        XCTAssertTrue(report.modErrorCounts.isEmpty)
    }

    func testLoadReportReflectsLogFileChanges() throws {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let logURL = folderURL.appendingPathComponent(SMAPILogReader.fileName)

        try fixtureLog.write(to: logURL, atomically: true, encoding: .utf8)
        let firstReport = try XCTUnwrap(SMAPILogReader.loadReport(inLogFolder: folderURL))
        XCTAssertEqual(firstReport.skippedMods.count, 2)
        XCTAssertNotNil(firstReport.generatedAt)

        try "[12:00:00 INFO  SMAPI] SMAPI 4.2.0 with Stardew Valley 1.6.16 on macOS"
            .write(to: logURL, atomically: true, encoding: .utf8)
        let secondReport = try XCTUnwrap(SMAPILogReader.loadReport(inLogFolder: folderURL))
        XCTAssertEqual(secondReport.smapiVersion, "4.2.0")
        XCTAssertTrue(secondReport.skippedMods.isEmpty)
    }
}

@MainActor
final class SMAPILogInsightsTests: SeedBoxTestCase {
    func testChoosingLogFolderSurfacesLastSessionIssuesForInstalledMods() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()

        for (folder, name) in [("BrokenMod", "Broken Mod"), ("FineMod", "Fine Mod")] {
            let modURL = install.modDirectoryURL.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
            try writeManifest(name: name, to: modURL)
        }

        let logFolderURL = temporaryDirectory.appendingPathComponent("ErrorLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: logFolderURL, withIntermediateDirectories: true)
        try """
        [12:00:00 INFO  SMAPI] SMAPI 4.1.10 with Stardew Valley 1.6.15 on macOS
        [12:00:04 ERROR SMAPI]       - Broken Mod 1.2.3 because it's no longer compatible.
        [12:00:04 ERROR SMAPI]       - Uninstalled Mod because its DLL is missing.
        [12:00:10 ERROR Fine Mod] Something failed
        """.write(
            to: logFolderURL.appendingPathComponent(SMAPILogReader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        XCTAssertFalse(viewModel.state.hasSMAPILogFolderAccess)

        await viewModel.chooseSMAPILogFolder(logFolderURL)

        XCTAssertTrue(viewModel.state.hasSMAPILogFolderAccess)
        let report = try XCTUnwrap(viewModel.state.lastSessionReport)
        XCTAssertEqual(report.smapiVersion, "4.1.10")

        let issues = viewModel.state.lastSessionIssues
        XCTAssertEqual(
            issues.map(\.mod.displayName).sorted(),
            ["Broken Mod", "Fine Mod"],
            "Issues for mods no longer installed are dropped."
        )
        let brokenIssue = try XCTUnwrap(issues.first { $0.mod.displayName == "Broken Mod" })
        XCTAssertEqual(brokenIssue.skippedReason, "it's no longer compatible.")
        let fineIssue = try XCTUnwrap(issues.first { $0.mod.displayName == "Fine Mod" })
        XCTAssertEqual(fineIssue.errorCount, 1)
        XCTAssertTrue(viewModel.state.hasProblems)

        let auditEntry = try XCTUnwrap(viewModel.state.auditTrail.recentEntries.last)
        XCTAssertEqual(auditEntry.action, .logFolderSelected)
    }

    func testLaunchAnnouncesProblematicSessionExactlyOnce() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let modURL = install.modDirectoryURL.appendingPathComponent("BrokenMod")
        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Broken Mod", to: modURL)

        let logFolderURL = temporaryDirectory.appendingPathComponent("ErrorLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: logFolderURL, withIntermediateDirectories: true)
        let logURL = logFolderURL.appendingPathComponent(SMAPILogReader.fileName)
        try """
        [12:00:00 INFO  SMAPI] SMAPI 4.1.10 with Stardew Valley 1.6.15 on macOS
        [12:00:04 ERROR SMAPI]       - Broken Mod 1.2.3 because it's no longer compatible.
        [12:00:10 ERROR Broken Mod] also threw an error
        """.write(to: logURL, atomically: true, encoding: .utf8)

        // First app session grants both folders.
        let setupViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await setupViewModel.chooseModsFolder(install.modDirectoryURL)
        await setupViewModel.chooseSMAPILogFolder(logFolderURL)

        // A fresh launch announces the problematic session.
        let firstLaunch = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await firstLaunch.refresh()

        let notice = try XCTUnwrap(firstLaunch.state.pendingLastSessionNotice)
        XCTAssertEqual(notice.skippedModCount, 1)
        XCTAssertEqual(notice.erroringModCount, 1)

        await firstLaunch.dismissLastSessionNotice()
        XCTAssertNil(firstLaunch.state.pendingLastSessionNotice)

        // The same session is never announced again on later launches.
        let secondLaunch = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await secondLaunch.refresh()
        XCTAssertNil(secondLaunch.state.pendingLastSessionNotice)

        // A newer log session is announced again.
        try """
        [13:00:00 INFO  SMAPI] SMAPI 4.1.10 with Stardew Valley 1.6.15 on macOS
        [13:00:04 ERROR SMAPI]       - Broken Mod 1.2.3 because it's no longer compatible.
        """.write(to: logURL, atomically: true, encoding: .utf8)

        let thirdLaunch = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await thirdLaunch.refresh()
        let newNotice = try XCTUnwrap(thirdLaunch.state.pendingLastSessionNotice)
        XCTAssertEqual(newNotice.skippedModCount, 1)
        XCTAssertEqual(newNotice.erroringModCount, 0)
    }

    func testActivationAnnouncesSessionWrittenWhileAppStayedOpen() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let modURL = install.modDirectoryURL.appendingPathComponent("BrokenMod")
        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Broken Mod", to: modURL)

        let logFolderURL = temporaryDirectory.appendingPathComponent("ErrorLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: logFolderURL, withIntermediateDirectories: true)
        let logURL = logFolderURL.appendingPathComponent(SMAPILogReader.fileName)
        try "[12:00:00 INFO  SMAPI] SMAPI 4.1.10 with Stardew Valley 1.6.15 on macOS"
            .write(to: logURL, atomically: true, encoding: .utf8)

        // Seed Box launches and stays open; the clean log announces nothing.
        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)
        await viewModel.chooseSMAPILogFolder(logFolderURL)
        await viewModel.refresh()
        XCTAssertNil(viewModel.state.pendingLastSessionNotice)

        // The game runs and crashes while Seed Box stays open: SMAPI
        // recreates the log (new creation date) with problems in it.
        try FileManager.default.removeItem(at: logURL)
        try """
        [13:00:00 INFO  SMAPI] SMAPI 4.1.10 with Stardew Valley 1.6.15 on macOS
        [13:00:04 ERROR SMAPI]       - Broken Mod 1.2.3 because it crashed during launch.
        """.write(to: logURL, atomically: true, encoding: .utf8)

        // The user returns to Seed Box.
        await viewModel.refreshAfterActivation()

        let notice = try XCTUnwrap(viewModel.state.pendingLastSessionNotice)
        XCTAssertEqual(notice.skippedModCount, 1)
        await viewModel.dismissLastSessionNotice()

        // The game keeps appending to the same session's log; tabbing back
        // again must not re-announce.
        let fileHandle = try FileHandle(forWritingTo: logURL)
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: Data("\n[13:05:00 ERROR Broken Mod] more errors\n".utf8))
        try fileHandle.close()

        await viewModel.refreshAfterActivation()
        XCTAssertNil(viewModel.state.pendingLastSessionNotice)

        // A brand-new game session announces again.
        try FileManager.default.removeItem(at: logURL)
        try """
        [14:00:00 INFO  SMAPI] SMAPI 4.1.10 with Stardew Valley 1.6.15 on macOS
        [14:00:04 ERROR SMAPI]       - Broken Mod 1.2.3 because it crashed again.
        """.write(to: logURL, atomically: true, encoding: .utf8)

        await viewModel.refreshAfterActivation()
        XCTAssertNotNil(viewModel.state.pendingLastSessionNotice)
    }

    func testLaunchWithCleanLogAnnouncesNothing() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let modURL = install.modDirectoryURL.appendingPathComponent("FineMod")
        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Fine Mod", to: modURL)

        let logFolderURL = temporaryDirectory.appendingPathComponent("ErrorLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: logFolderURL, withIntermediateDirectories: true)
        try "[12:00:00 INFO  SMAPI] SMAPI 4.1.10 with Stardew Valley 1.6.15 on macOS"
            .write(
                to: logFolderURL.appendingPathComponent(SMAPILogReader.fileName),
                atomically: true,
                encoding: .utf8
            )

        let setupViewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await setupViewModel.chooseModsFolder(install.modDirectoryURL)
        await setupViewModel.chooseSMAPILogFolder(logFolderURL)

        let launch = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await launch.refresh()

        XCTAssertNil(launch.state.pendingLastSessionNotice)
    }

    func testChoosingFolderWithoutLogRecordsGuidance() async throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let emptyFolderURL = temporaryDirectory.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyFolderURL, withIntermediateDirectories: true)

        let viewModel = ModManagerViewModel(
            defaults: defaults,
            modSetDirectory: install.modSetDirectoryURL
        )
        await viewModel.chooseModsFolder(install.modDirectoryURL)

        await viewModel.chooseSMAPILogFolder(emptyFolderURL)

        XCTAssertTrue(viewModel.state.hasSMAPILogFolderAccess)
        XCTAssertNil(viewModel.state.lastSessionReport)
        XCTAssertTrue(viewModel.state.lastSessionIssues.isEmpty)
    }
}
