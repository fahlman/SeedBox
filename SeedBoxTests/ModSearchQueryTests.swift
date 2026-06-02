import XCTest
@testable import SeedBox

final class ModSearchQueryTests: SeedBoxTestCase {
    func testMatchesColumnFilters() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let smapiURL = install.modDirectoryURL.appendingPathComponent("SaveBackup")
        let contentPackURL = install.modDirectoryURL.appendingPathComponent(".ExamplePack")

        try FileManager.default.createDirectory(at: smapiURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contentPackURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Save Backup",
            to: smapiURL,
            author: "ConcernedApe"
        )
        try writeManifest(
            name: "Example Pack",
            to: contentPackURL,
            author: "Pathoschild Games",
            contentPackForUniqueID: "Pathoschild.ContentPatcher"
        )

        let mods = try ModLibrary.scan(install: install)
        let enabledSMAPIMatches = mods.filter {
            ModSearchQuery("state:enabled type:smapi author:ConcernedApe").matches($0)
        }
        let disabledContentPackMatches = mods.filter {
            ModSearchQuery("state:disabled type:content-patcher mod:Example").matches($0)
        }
        let quotedAuthorMatches = mods.filter {
            ModSearchQuery("author:\"Pathoschild Games\"").matches($0)
        }

        XCTAssertEqual(enabledSMAPIMatches.map(\.displayName), ["Save Backup"])
        XCTAssertEqual(disabledContentPackMatches.map(\.displayName), ["Example Pack"])
        XCTAssertEqual(quotedAuthorMatches.map(\.displayName), ["Example Pack"])
    }
}
