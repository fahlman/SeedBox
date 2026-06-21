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
        XCTAssertEqual(summary.archiveByteCount, archiveData.count)
        XCTAssertTrue(archiveData.starts(with: Data([0x50, 0x4B])))
    }

    func testNoDiagnosticsExportDoesNotReplaceDestinationFile() throws {
        let diagnosticsDirectory = temporaryDirectory.appendingPathComponent("Empty Diagnostics", isDirectory: true)
        let archiveURL = temporaryDirectory.appendingPathComponent("Existing.zip")
        let existingData = Data("keep me".utf8)
        try FileManager.default.createDirectory(at: diagnosticsDirectory, withIntermediateDirectories: true)
        try existingData.write(to: archiveURL)

        XCTAssertThrowsError(
            try CrashDiagnosticsExporter.exportArchive(
                from: diagnosticsDirectory,
                to: archiveURL,
                fileManager: .default
            )
        ) { error in
            XCTAssertEqual(error as? CrashDiagnosticsExportError, .noDiagnostics)
        }
        XCTAssertEqual(try Data(contentsOf: archiveURL), existingData)
    }
}
