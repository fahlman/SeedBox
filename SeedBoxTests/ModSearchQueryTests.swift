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
            author: "ConcernedApe",
            description: "Backs up saves before launch."
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
        let descriptionMatches = mods.filter {
            ModSearchQuery("mod:\"backs up\"").matches($0)
        }
        let quotedAuthorMatches = mods.filter {
            ModSearchQuery("author:\"Pathoschild Games\"").matches($0)
        }

        XCTAssertEqual(enabledSMAPIMatches.map(\.displayName), ["Save Backup"])
        XCTAssertEqual(disabledContentPackMatches.map(\.displayName), ["Example Pack"])
        XCTAssertEqual(descriptionMatches.map(\.displayName), ["Save Backup"])
        XCTAssertEqual(quotedAuthorMatches.map(\.displayName), ["Example Pack"])
    }

    func testMatchesDependencyFilters() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let contentPatcherURL = install.modDirectoryURL.appendingPathComponent(".ContentPatcher")
        let expandedURL = install.modDirectoryURL.appendingPathComponent("StardewValleyExpanded")

        try FileManager.default.createDirectory(at: contentPatcherURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: expandedURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Content Patcher",
            to: contentPatcherURL,
            uniqueID: "Pathoschild.ContentPatcher"
        )
        try writeManifest(
            name: "Stardew Valley Expanded",
            to: expandedURL,
            uniqueID: "FlashShifter.StardewValleyExpandedCP",
            contentPackForUniqueID: "Pathoschild.ContentPatcher"
        )

        let mods = try ModLibrary.scan(install: install)
        let graph = ModDependencyGraph(mods: mods)
        let disabledDependencyMatches = mods.filter {
            ModSearchQuery("dependency:disabled").matches($0, in: graph)
        }
        let requiresContentPatcherMatches = mods.filter {
            ModSearchQuery("requires:\"Content Patcher\"").matches($0, in: graph)
        }
        let requiredByExpandedMatches = mods.filter {
            ModSearchQuery("requiredby:\"Stardew Valley Expanded\"").matches($0, in: graph)
        }

        XCTAssertEqual(disabledDependencyMatches.map(\.displayName), ["Stardew Valley Expanded"])
        XCTAssertEqual(requiresContentPatcherMatches.map(\.displayName), ["Stardew Valley Expanded"])
        XCTAssertEqual(requiredByExpandedMatches.map(\.displayName), ["Content Patcher"])
    }
}
