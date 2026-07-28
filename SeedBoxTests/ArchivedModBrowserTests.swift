import XCTest
@testable import SeedBox

final class ArchivedModBrowserTests: XCTestCase {
    func testFiltersArchivedModsBySearchTextAndReason() {
        let deleted = makeArchivedMod(
            name: "Content Patcher",
            author: "Pathoschild",
            version: "1.0.0",
            folderName: "ContentPatcher",
            reason: .deleted
        )
        let updated = makeArchivedMod(
            name: "Farm Expansion",
            author: "Example Author",
            version: "2.0.0",
            folderName: "FarmExpansion",
            reason: .updated
        )
        let archivedMods = [deleted, updated]

        XCTAssertEqual(
            ArchivedModBrowser
                .filteredArchivedMods(archivedMods, searchText: "pathos 1.0", reasonFilter: .deleted)
                .map(\.folderName),
            ["ContentPatcher"]
        )
        XCTAssertEqual(
            ArchivedModBrowser
                .filteredArchivedMods(archivedMods, searchText: "farm", reasonFilter: .all)
                .map(\.folderName),
            ["FarmExpansion"]
        )
        XCTAssertTrue(
            ArchivedModBrowser
                .filteredArchivedMods(archivedMods, searchText: "content", reasonFilter: .updated)
                .isEmpty
        )
    }

    private func makeArchivedMod(
        name: String,
        author: String,
        version: String,
        folderName: String,
        reason: ModArchiveReason
    ) -> ArchivedModInfo {
        let containerURL = URL(fileURLWithPath: "/tmp/archive/\(folderName)", isDirectory: true)
        return ArchivedModInfo(
            url: containerURL.appendingPathComponent(folderName, isDirectory: true),
            containerURL: containerURL,
            folderName: folderName,
            reason: reason,
            archivedDate: Date(timeIntervalSince1970: 1_750_000_000),
            manifest: ModManifest(
                name: name,
                author: author,
                version: version,
                description: nil,
                uniqueID: "Test.\(folderName)",
                entryDll: nil,
                minimumApiVersion: nil,
                updateKeys: nil,
                contentPackFor: nil,
                dependencies: nil
            )
        )
    }
}
