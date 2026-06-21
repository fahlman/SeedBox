import XCTest
@testable import SeedBox

final class CrashDiagnosticsCollectorTests: SeedBoxTestCase {
    func testStoresPayloadAsTimestampedJSONFile() throws {
        let diagnosticsDirectory = temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        let collector = CrashDiagnosticsCollector(diagnosticsDirectory: diagnosticsDirectory)
        let payload = Data(#"{"crashDiagnostics": []}"#.utf8)

        let receivedAt = Date(timeIntervalSince1970: 1_750_000_000)
        collector.store(payload, receivedAt: receivedAt)
        collector.store(payload, receivedAt: receivedAt)

        let storedFiles = try FileManager.default.contentsOfDirectory(atPath: diagnosticsDirectory.path)
            .sorted()
        XCTAssertEqual(storedFiles.count, 2)
        XCTAssertTrue(storedFiles.allSatisfy { $0.hasPrefix("Diagnostic ") && $0.hasSuffix(".json") })
        XCTAssertEqual(
            try Data(contentsOf: diagnosticsDirectory.appendingPathComponent(storedFiles[0])),
            payload
        )
    }

    func testFindsOnlyJSONDiagnosticPayloadsSortedByName() throws {
        let diagnosticsDirectory = temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: diagnosticsDirectory.appendingPathComponent("B.json"))
        try Data("{}".utf8).write(to: diagnosticsDirectory.appendingPathComponent("A.json"))
        try Data("ignored".utf8).write(to: diagnosticsDirectory.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(
            at: diagnosticsDirectory.appendingPathComponent("Nested.json", isDirectory: true),
            withIntermediateDirectories: true
        )

        let payloads = try CrashDiagnosticsExporter.diagnosticPayloadURLs(
            in: diagnosticsDirectory,
            fileManager: .default
        )

        XCTAssertEqual(payloads.map(\.lastPathComponent), ["A.json", "B.json"])
    }

    func testBuildsDiagnosticSummaryFromStoredPayloads() throws {
        let diagnosticsDirectory = temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        let olderDate = Date(timeIntervalSince1970: 1_750_000_000)
        let newerDate = olderDate.addingTimeInterval(60 * 60)
        let olderPayload = diagnosticsDirectory.appendingPathComponent("A.json")
        let newerPayload = diagnosticsDirectory.appendingPathComponent("B.json")
        try Data("{}".utf8).write(to: olderPayload)
        try Data("{}".utf8).write(to: newerPayload)
        try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: olderPayload.path)
        try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: newerPayload.path)

        let summary = CrashDiagnosticsExporter.diagnosticSummary(
            in: diagnosticsDirectory,
            fileManager: .default
        )

        XCTAssertEqual(summary.payloadCount, 2)
        XCTAssertEqual(
            try XCTUnwrap(summary.mostRecentPayloadDate).timeIntervalSince1970,
            newerDate.timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertTrue(summary.hasRecentPayloads(asOf: newerDate.addingTimeInterval(60)))
        XCTAssertFalse(summary.hasRecentPayloads(asOf: newerDate.addingTimeInterval(CrashDiagnosticsSummary.recentPayloadInterval + 60)))
    }

    func testPostsNotificationWhenDiagnosticPayloadIsStored() {
        let diagnosticsDirectory = temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        let collector = CrashDiagnosticsCollector(diagnosticsDirectory: diagnosticsDirectory)
        let expectation = expectation(
            forNotification: CrashDiagnosticsCollector.didStorePayloadNotification,
            object: collector
        )

        collector.store(Data(#"{"crashDiagnostics": []}"#.utf8), receivedAt: Date(timeIntervalSince1970: 1_750_000_000))

        wait(for: [expectation], timeout: 1)
    }

    func testExportsDiagnosticPayloadsAsZipArchive() throws {
        let diagnosticsDirectory = temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        let archiveURL = temporaryDirectory.appendingPathComponent("Seed Box Diagnostics.zip")
        try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        try Data(#"{"first": true}"#.utf8)
            .write(to: diagnosticsDirectory.appendingPathComponent("First.json"))
        try Data(#"{"second": true}"#.utf8)
            .write(to: diagnosticsDirectory.appendingPathComponent("Second.json"))

        let summary = try CrashDiagnosticsExporter.exportArchive(
            from: diagnosticsDirectory,
            to: archiveURL,
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            fileManager: .default
        )

        let archiveData = try Data(contentsOf: archiveURL)
        XCTAssertEqual(summary.payloadCount, 2)
        XCTAssertEqual(summary.supportFileCount, 4)
        XCTAssertEqual(summary.archiveByteCount, archiveData.count)
        XCTAssertTrue(archiveData.starts(with: Data([0x50, 0x4B])))
    }

    func testExportsSupportBundleWithoutDiagnosticPayloads() throws {
        let diagnosticsDirectory = temporaryDirectory.appendingPathComponent("Empty Diagnostics", isDirectory: true)
        let archiveURL = temporaryDirectory.appendingPathComponent("Seed Box Diagnostics.zip")
        try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)

        let summary = try CrashDiagnosticsExporter.exportArchive(
            from: diagnosticsDirectory,
            to: archiveURL,
            context: CrashDiagnosticsExportContext(appVersion: "1.2.3", buildVersion: "4", state: nil),
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            fileManager: .default
        )

        let archiveData = try Data(contentsOf: archiveURL)
        XCTAssertEqual(summary.payloadCount, 0)
        XCTAssertEqual(summary.supportFileCount, 2)
        XCTAssertEqual(summary.archiveByteCount, archiveData.count)
        XCTAssertTrue(archiveData.starts(with: Data([0x50, 0x4B])))
    }

    func testWritesSupportBundleWithSafeStateSummaries() throws {
        let install = try makeInstall()
        let modURL = try makeInstalledMod(
            name: "Sample Mod",
            in: install,
            folderName: "SampleMod",
            uniqueID: "Example.SampleMod",
            updateKeys: ["Nexus:123"]
        )
        let state = makeDiagnosticsState(
            install: install,
            mods: [
                ModInfo(
                    folderName: "SampleMod",
                    url: modURL,
                    isEnabled: true,
                    manifest: ModManifest(
                        name: "Sample Mod",
                        author: "Test Author",
                        version: "1.2.3",
                        description: "A test mod.",
                        uniqueID: "Example.SampleMod",
                        entryDll: "SampleMod.dll",
                        minimumApiVersion: nil,
                        updateKeys: ["Nexus:123"],
                        contentPackFor: nil,
                        dependencies: nil
                    )
                )
            ]
        )
        let bundleDirectory = temporaryDirectory.appendingPathComponent("Bundle", isDirectory: true)

        let summary = try CrashDiagnosticsExporter.writeSupportBundle(
            to: bundleDirectory,
            payloadURLs: [],
            context: CrashDiagnosticsExportContext(appVersion: "1.2.3", buildVersion: "4", state: state),
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            fileManager: .default
        )

        let files = try FileManager.default.contentsOfDirectory(atPath: bundleDirectory.path)
        XCTAssertEqual(summary.payloadCount, 0)
        XCTAssertEqual(summary.supportFileCount, 5)
        XCTAssertTrue(files.contains("README.txt"))
        XCTAssertTrue(files.contains("App Summary.json"))
        XCTAssertTrue(files.contains("Settings Summary.json"))
        XCTAssertTrue(files.contains("Mod Inventory Summary.json"))
        XCTAssertTrue(files.contains("Audit Summary.json"))

        let readme = try String(contentsOf: bundleDirectory.appendingPathComponent("README.txt"), encoding: .utf8)
        XCTAssertTrue(readme.contains("does not include mod files"))

        let appSummary = try String(contentsOf: bundleDirectory.appendingPathComponent("App Summary.json"), encoding: .utf8)
        XCTAssertTrue(appSummary.contains(#""appVersion" : "1.2.3""#))

        let inventorySummary = try String(contentsOf: bundleDirectory.appendingPathComponent("Mod Inventory Summary.json"), encoding: .utf8)
        XCTAssertTrue(inventorySummary.contains("Sample Mod"))
        XCTAssertFalse(inventorySummary.contains(temporaryDirectory.path))
    }

    func testSupportBundleRedactsKnownPrivatePathsFromAuditSummary() throws {
        let install = try makeInstall()
        let modURL = try makeInstalledMod(name: "Private Path Mod", in: install)
        let entry = AuditLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_750_000_000),
            action: .modsAdded,
            summary: "Added \(modURL.path)",
            modsDirectoryPath: install.modDirectoryURL.path,
            selectedModSetID: ModSetStore.defaultSetID,
            selectedModSetName: ModSetStore.defaultSetName,
            appliedModSetID: ModSetStore.defaultSetID,
            subjects: [
                AuditLogSubject(
                    kind: .mod,
                    id: "Example.PrivatePathMod",
                    name: "Private Path Mod",
                    path: modURL.path
                )
            ],
            details: [
                "source": modURL.path,
                "note": "safe detail"
            ]
        )
        let state = makeDiagnosticsState(
            install: install,
            mods: [
                ModInfo(
                    folderName: modURL.lastPathComponent,
                    url: modURL,
                    isEnabled: true,
                    manifest: nil
                )
            ],
            auditEntries: [entry]
        )
        let bundleDirectory = temporaryDirectory.appendingPathComponent("Bundle", isDirectory: true)

        try CrashDiagnosticsExporter.writeSupportBundle(
            to: bundleDirectory,
            payloadURLs: [],
            context: CrashDiagnosticsExportContext(appVersion: "1.2.3", buildVersion: "4", state: state),
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            fileManager: .default
        )

        let auditSummary = try String(contentsOf: bundleDirectory.appendingPathComponent("Audit Summary.json"), encoding: .utf8)
        XCTAssertTrue(auditSummary.contains("[redacted path]"))
        XCTAssertTrue(auditSummary.contains("safe detail"))
        XCTAssertFalse(auditSummary.contains(temporaryDirectory.path))
    }

    private func makeDiagnosticsState(
        install: StardewInstall,
        mods: [ModInfo] = [],
        auditEntries: [AuditLogEntry] = []
    ) -> ModManagerState {
        ModManagerState(
            modsDirectoryPath: install.modDirectoryURL.path,
            status: install.status(),
            hasSavedFolderAccess: true,
            mods: mods,
            invalidModFolders: [],
            archivedMods: [],
            archiveSummary: ModArchiveSummary(),
            archiveSettings: ArchiveSettings(
                automaticallyPrunesExpiredArchives: false,
                retentionDays: ArchiveSettings.defaultRetentionDays
            ),
            hasLoadedMods: true,
            modSets: [
                ModSet(
                    id: ModSetStore.defaultSetID,
                    name: ModSetStore.defaultSetName,
                    disabledFolderNames: [],
                    isEditable: false
                )
            ],
            selectedModSetID: ModSetStore.defaultSetID,
            appliedModSetID: ModSetStore.defaultSetID,
            activityStatus: nil,
            auditTrail: AuditTrailState(
                logPath: install.auditLogURL.path,
                recentEntries: auditEntries,
                lastErrorMessage: nil
            ),
            pendingSourceCleanupOffer: nil
        )
    }
}
