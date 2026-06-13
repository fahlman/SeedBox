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
}
