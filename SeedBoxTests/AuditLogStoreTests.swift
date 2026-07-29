import XCTest
@testable import SeedBox

final class AuditLogStoreTests: SeedBoxTestCase {
    func testAppendReturnsTheExactPersistedRepresentation() throws {
        let logURL = temporaryDirectory.appendingPathComponent("Audit Log.plist")
        var originalEntry = entry(0)
        originalEntry.timestamp = Date(timeIntervalSince1970: 123.75)

        let recentEntries = try AuditLogStore.append(originalEntry, to: logURL)
        let persistedEntries = try AuditLogStore.loadEntries(from: logURL)

        XCTAssertEqual(recentEntries, persistedEntries)
        XCTAssertEqual(recentEntries.first?.timestamp.timeIntervalSince1970, 123)
    }

    func testAppendReturnsRecentTailAndBoundsPersistedHistory() throws {
        let logURL = temporaryDirectory.appendingPathComponent("Audit Log.plist")

        for index in 0..<(AuditLogStore.recentEntryLimit + 3) {
            let recentEntries = try AuditLogStore.append(
                entry(index),
                to: logURL,
                retentionLimit: AuditLogStore.recentEntryLimit + 1
            )

            XCTAssertLessThanOrEqual(
                recentEntries.count,
                AuditLogStore.recentEntryLimit
            )
            XCTAssertEqual(recentEntries.last?.summary, "Entry \(index)")
        }

        let persistedEntries = try AuditLogStore.loadEntries(from: logURL)
        XCTAssertEqual(
            persistedEntries.count,
            AuditLogStore.recentEntryLimit + 1
        )
        XCTAssertEqual(persistedEntries.first?.summary, "Entry 2")
        XCTAssertEqual(persistedEntries.last?.summary, "Entry 102")
    }

    private func entry(_ index: Int) -> AuditLogEntry {
        AuditLogEntry(
            action: .modEnabled,
            summary: "Entry \(index)",
            modsDirectoryPath: "/tmp/Mods",
            selectedModSetID: ModSetStore.defaultSetID,
            selectedModSetName: AppStrings.ModSetNames.defaultSet,
            appliedModSetID: ModSetStore.defaultSetID
        )
    }
}
