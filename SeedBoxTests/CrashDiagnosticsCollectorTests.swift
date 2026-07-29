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
        let outsidePayload = temporaryDirectory.appendingPathComponent("Outside.json")
        try Data("{}".utf8).write(to: outsidePayload)
        try FileManager.default.createSymbolicLink(
            at: diagnosticsDirectory.appendingPathComponent("Linked.json"),
            withDestinationURL: outsidePayload
        )

        let payloads = try CrashDiagnosticsExporter.diagnosticPayloadURLs(
            in: diagnosticsDirectory,
            fileManager: .default
        )

        XCTAssertEqual(payloads.map(\.lastPathComponent), ["A.json", "B.json"])
    }

    func testSupportBundleRejectsOversizedDiagnosticPayload() throws {
        let payloadURL = temporaryDirectory.appendingPathComponent("Large.json")
        let bundleDirectory = temporaryDirectory.appendingPathComponent(
            "Bundle",
            isDirectory: true
        )
        try Data(#"{"value":true}"#.utf8).write(to: payloadURL)
        let limits = CrashDiagnosticsExportLimits(
            maximumPayloadCount: 1,
            maximumPayloadByteCount: 4,
            maximumTotalPayloadByteCount: 4
        )

        XCTAssertThrowsError(
            try CrashDiagnosticsExporter.writeSupportBundle(
                to: bundleDirectory,
                payloadURLs: [payloadURL],
                context: CrashDiagnosticsExportContext(
                    appVersion: "1",
                    buildVersion: "1",
                    state: nil
                ),
                generatedAt: Date(),
                limits: limits
            )
        ) { error in
            XCTAssertEqual(
                error as? CrashDiagnosticsExportError,
                .payloadTooLarge(
                    fileName: "Large.json",
                    maximumByteCount: 4
                )
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundleDirectory.path))
    }

    func testAbandonedDiagnosticsCleanupRequiresMarker() throws {
        let temporaryRoot = temporaryDirectory.appendingPathComponent(
            "Temporary",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        let markedDirectory = try SecureTemporaryWorkspace.create(
            in: temporaryRoot,
            prefix: CrashDiagnosticsExporter.stagingDirectoryPrefix,
            markerFileName: CrashDiagnosticsExporter.stagingMarkerFileName
        )
        let unmarkedDirectory = temporaryRoot.appendingPathComponent(
            "\(CrashDiagnosticsExporter.stagingDirectoryPrefix)unmarked",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: unmarkedDirectory,
            withIntermediateDirectories: false
        )
        let oldDate = Date().addingTimeInterval(
            -CrashDiagnosticsExporter.abandonedStagingAge - 60
        )
        for directory in [markedDirectory, unmarkedDirectory] {
            try FileManager.default.setAttributes(
                [.modificationDate: oldDate],
                ofItemAtPath: directory.path
            )
        }

        CrashDiagnosticsExporter.removeAbandonedStagingDirectories(
            in: temporaryRoot
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: markedDirectory.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: unmarkedDirectory.path)
        )
    }

    func testSecureTemporaryWorkspaceUsesOwnerOnlyPermissions() throws {
        let temporaryRoot = temporaryDirectory.appendingPathComponent(
            "Temporary",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )

        let workspace = try SecureTemporaryWorkspace.create(
            in: temporaryRoot,
            prefix: "SeedBoxTest-",
            markerFileName: ".seedbox-test"
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: workspace.path
        )

        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )
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

    func testPrunesPayloadsByAgeCountAndTotalSize() throws {
        let diagnosticsDirectory = temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        let collector = CrashDiagnosticsCollector(
            diagnosticsDirectory: diagnosticsDirectory,
            retentionInterval: 100,
            maximumPayloadCount: 2,
            maximumByteCount: 12
        )
        try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        let referenceDate = Date(timeIntervalSince1970: 2_000)

        for (name, date) in [
            ("Expired.json", referenceDate.addingTimeInterval(-101)),
            ("Older.json", referenceDate.addingTimeInterval(-30)),
            ("Newer.json", referenceDate.addingTimeInterval(-20)),
            ("Newest.json", referenceDate.addingTimeInterval(-10))
        ] {
            let url = diagnosticsDirectory.appendingPathComponent(name)
            try Data("123456".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.path
            )
        }

        try collector.pruneStoredPayloads(referenceDate: referenceDate)

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: diagnosticsDirectory.path).sorted(),
            ["Newer.json", "Newest.json"]
        )
    }

    func testDeletesAllStoredPayloadsWithoutRemovingOtherFiles() throws {
        let diagnosticsDirectory = temporaryDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
        let collector = CrashDiagnosticsCollector(diagnosticsDirectory: diagnosticsDirectory)
        try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: diagnosticsDirectory.appendingPathComponent("Payload.json"))
        try Data("keep".utf8).write(to: diagnosticsDirectory.appendingPathComponent("README.txt"))

        try collector.deleteAllStoredPayloads()

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: diagnosticsDirectory.path),
            ["README.txt"]
        )
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
                    id: "\(modURL.path)#private-mod-id",
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

    func testSupportBundleRedactsEveryStringInMetricKitPayloads() throws {
        let payloadURL = temporaryDirectory.appendingPathComponent("Payload.json")
        let bundleDirectory = temporaryDirectory.appendingPathComponent("Bundle", isDirectory: true)
        try Data(
            #"""
            {
              "path": "/Users/ryan/Library/Containers/com.example/private.json",
              "nested": ["Loaded file:///private/var/tmp/example.txt", "safe value"]
            }
            """#.utf8
        ).write(to: payloadURL)

        try CrashDiagnosticsExporter.writeSupportBundle(
            to: bundleDirectory,
            payloadURLs: [payloadURL],
            context: CrashDiagnosticsExportContext(
                appVersion: "1.2.3",
                buildVersion: "4",
                state: nil
            ),
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            fileManager: .default
        )

        let sanitizedPayload = try String(
            contentsOf: bundleDirectory
                .appendingPathComponent("MetricKit Payloads", isDirectory: true)
                .appendingPathComponent("Payload.json"),
            encoding: .utf8
        )
        XCTAssertTrue(sanitizedPayload.contains("[redacted path]"))
        XCTAssertTrue(sanitizedPayload.contains("safe value"))
        XCTAssertFalse(sanitizedPayload.contains("/Users/ryan"))
        XCTAssertFalse(sanitizedPayload.contains("/private/var/tmp"))
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
