import XCTest
@testable import SeedBox

final class FileMoveTransactionTests: SeedBoxTestCase {
    func testFailedMoveRollsBackCompletedMovesAndRemovesJournal() throws {
        let sourceA = try makeDirectory(named: "A")
        let sourceB = try makeDirectory(named: "B")
        let destinationA = temporaryDirectory.appendingPathComponent(".A")
        let destinationB = temporaryDirectory.appendingPathComponent(".B")
        var moveCount = 0

        XCTAssertThrowsError(
            try FileMoveTransaction.perform(
                [
                    FileMoveOperation(sourceURL: sourceA, destinationURL: destinationA),
                    FileMoveOperation(sourceURL: sourceB, destinationURL: destinationB)
                ],
                journalDirectoryURL: temporaryDirectory,
                moveItem: { sourceURL, destinationURL in
                    moveCount += 1
                    if moveCount == 2 {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                }
            )
        )

        XCTAssertTrue(FileManager.default.directoryExists(at: sourceA))
        XCTAssertTrue(FileManager.default.directoryExists(at: sourceB))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationB.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: temporaryDirectory
                .appendingPathComponent(FileMoveTransaction.journalFileName)
                .path
        ))
    }

    func testRecoveryReversesMovesCompletedBeforeInterruption() throws {
        let sourceA = try makeDirectory(named: "A")
        let sourceB = try makeDirectory(named: "B")
        let destinationA = temporaryDirectory.appendingPathComponent(".A")
        let destinationB = temporaryDirectory.appendingPathComponent(".B")
        let operations = [
            FileMoveOperation(sourceURL: sourceA, destinationURL: destinationA),
            FileMoveOperation(sourceURL: sourceB, destinationURL: destinationB)
        ]
        try FileManager.default.moveItem(at: sourceA, to: destinationA)
        try writeJournal(operations: operations)

        try FileMoveTransaction.recoverIfNeeded(in: temporaryDirectory)

        XCTAssertTrue(FileManager.default.directoryExists(at: sourceA))
        XCTAssertTrue(FileManager.default.directoryExists(at: sourceB))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationB.path))
    }

    func testApplyingModSetDoesNotLeavePartialEnabledStates() throws {
        let install = try makeInstall()
        try makeInstalledMod(name: "Alpha", in: install)
        try makeInstalledMod(name: "Bravo", in: install)
        let set = ModSet(
            id: "none-for-test",
            name: "None",
            disabledFolderNames: ["Alpha", "Bravo"]
        )
        var moveCount = 0

        XCTAssertThrowsError(
            try ModSetStore.applySet(
                set,
                install: install,
                moveItem: { sourceURL, destinationURL in
                    moveCount += 1
                    if moveCount == 2 {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                }
            )
        )

        XCTAssertTrue(FileManager.default.directoryExists(
            at: install.modDirectoryURL.appendingPathComponent("Alpha")
        ))
        XCTAssertTrue(FileManager.default.directoryExists(
            at: install.modDirectoryURL.appendingPathComponent("Bravo")
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: install.modDirectoryURL.appendingPathComponent(".Alpha").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: install.modDirectoryURL.appendingPathComponent(".Bravo").path
        ))
    }

    func testFailedRestoreReturnsInstalledAndArchivedVersionsToOriginalLocations() throws {
        let install = try makeInstall()
        let oldURL = try makeInstalledMod(
            name: "Example",
            in: install,
            version: "1.0.0",
            uniqueID: "Test.Example"
        )
        let archivedOldURL = try ModArchive.archive(
            oldURL,
            in: install.archivedModsDirectoryURL,
            reason: .updated
        )
        let currentURL = try makeInstalledMod(
            name: "Example",
            in: install,
            version: "2.0.0",
            uniqueID: "Test.Example"
        )
        let archivedMod = try XCTUnwrap(
            ModArchive.archivedMods(in: install.archivedModsDirectoryURL)
                .first { $0.url == archivedOldURL }
        )
        var moveCount = 0

        XCTAssertThrowsError(
            try ModLibrary.restoreArchivedMods(
                [archivedMod],
                into: install,
                moveItem: { sourceURL, destinationURL in
                    moveCount += 1
                    if moveCount == 2 {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                }
            )
        )

        XCTAssertTrue(FileManager.default.directoryExists(at: currentURL))
        XCTAssertTrue(FileManager.default.directoryExists(at: archivedOldURL))
        let currentManifest = ModManifestReader.loadManifest(
            at: currentURL.appendingPathComponent("manifest.json")
        )
        XCTAssertEqual(currentManifest?.version, "2.0.0")
    }

    func testFailedUpdateRestoresInstalledVersionAndRemovesStaging() throws {
        let install = try makeInstall()
        let currentURL = try makeInstalledMod(
            name: "Example",
            in: install,
            version: "1.0.0",
            uniqueID: "Test.Example"
        )
        let downloadsURL = try makeDownloadsDirectory()
        let updateURL = try makeModPackage(
            name: "Example",
            in: downloadsURL,
            version: "2.0.0",
            uniqueID: "Test.Example"
        )
        var moveCount = 0

        XCTAssertThrowsError(
            try ModLibrary.installMods(
                from: [updateURL],
                into: install,
                replacementPolicy: .replaceExisting,
                moveItem: { sourceURL, destinationURL in
                    moveCount += 1
                    if moveCount == 2 {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                }
            )
        )

        let currentManifest = ModManifestReader.loadManifest(
            at: currentURL.appendingPathComponent("manifest.json")
        )
        XCTAssertEqual(currentManifest?.version, "1.0.0")
        XCTAssertTrue(FileManager.default.directoryExists(at: updateURL))
        let modDirectoryChildren = try FileManager.default.contentsOfDirectory(
            at: install.modDirectoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(modDirectoryChildren.contains {
            $0.lastPathComponent.hasPrefix(ModInstallWorkflow.installStagingDirectoryPrefix)
        })
    }

    private func makeDirectory(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeJournal(operations: [FileMoveOperation]) throws {
        struct TestJournal: Codable {
            var schemaVersion: Int
            var operations: [FileMoveOperation]
        }

        let data = try PropertyListEncoder().encode(
            TestJournal(schemaVersion: 1, operations: operations)
        )
        try data.write(
            to: temporaryDirectory.appendingPathComponent(
                FileMoveTransaction.journalFileName
            )
        )
    }
}
