import CoreSpotlight
import XCTest
@testable import SeedBox

final class SeedBoxSpotlightIndexTests: SeedBoxTestCase {
    func testBuildsSearchableItemsForModsSetsAndSmartSets() throws {
        let mod = ModInfo(
            folderName: "ContentPatcher",
            url: URL(fileURLWithPath: "/Users/someone/Stardew/Mods/ContentPatcher"),
            isEnabled: true,
            manifest: ModManifest(
                name: "Content Patcher",
                author: "Pathoschild",
                version: "2.0.0",
                description: nil,
                uniqueID: "Pathoschild.ContentPatcher",
                entryDll: nil,
                minimumApiVersion: nil,
                updateKeys: nil,
                contentPackFor: nil,
                dependencies: nil
            )
        )
        let set = ModSet(id: "favorites", name: "Favorites", disabledFolderNames: [])
        let smartSet = UserSmartModSet(id: "recent", name: "Recent", searchText: "")

        let items = SeedBoxSpotlightIndex.searchableItems(
            mods: [mod],
            modSets: [set],
            userSmartModSets: [smartSet]
        )

        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.domainIdentifier == SeedBoxSpotlightIndex.domainIdentifier })

        let modItem = try XCTUnwrap(items.first { $0.uniqueIdentifier == "seedbox:mod:\(mod.id)" })
        XCTAssertEqual(modItem.attributeSet.title, "Content Patcher")
        XCTAssertEqual(modItem.attributeSet.keywords, ["Pathoschild", "2.0.0", "ContentPatcher"])

        XCTAssertTrue(items.contains { $0.uniqueIdentifier == "seedbox:modSet:favorites" })
        XCTAssertTrue(items.contains { $0.uniqueIdentifier == "seedbox:userSmartModSet:recent" })
    }

    func testSearchableItemsContainNoPrivatePaths() throws {
        let mod = ModInfo(
            folderName: "ContentPatcher",
            url: URL(fileURLWithPath: "/Users/someone/Library/Stardew/Mods/ContentPatcher"),
            isEnabled: true,
            manifest: ModManifest(
                name: "Content Patcher",
                author: "Pathoschild",
                version: "2.0.0",
                description: nil,
                uniqueID: "Pathoschild.ContentPatcher",
                entryDll: nil,
                minimumApiVersion: nil,
                updateKeys: nil,
                contentPackFor: nil,
                dependencies: nil
            )
        )

        let item = try XCTUnwrap(
            SeedBoxSpotlightIndex.searchableItems(mods: [mod], modSets: [], userSmartModSets: []).first
        )
        let indexedText = [
            item.attributeSet.title,
            item.attributeSet.displayName,
            item.attributeSet.contentDescription,
            item.attributeSet.keywords?.joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        XCTAssertFalse(indexedText.contains("/Users/"))
        XCTAssertFalse(indexedText.contains("Library"))
    }

    func testRouteMappingRoundTripsEachKind() throws {
        XCTAssertEqual(
            SeedBoxSpotlightIndex.route(forSpotlightIdentifier: "seedbox:mod:abc#def"),
            .mod(id: "abc#def")
        )
        XCTAssertEqual(
            SeedBoxSpotlightIndex.route(forSpotlightIdentifier: "seedbox:modSet:favorites"),
            .modSet(id: "favorites")
        )
        XCTAssertEqual(
            SeedBoxSpotlightIndex.route(forSpotlightIdentifier: "seedbox:userSmartModSet:recent"),
            .userSmartModSet(id: "recent")
        )
    }

    func testRouteMappingRejectsUnknownIdentifiers() throws {
        XCTAssertNil(SeedBoxSpotlightIndex.route(forSpotlightIdentifier: "other:mod:x"))
        XCTAssertNil(SeedBoxSpotlightIndex.route(forSpotlightIdentifier: "seedbox:archive:x"))
        XCTAssertNil(SeedBoxSpotlightIndex.route(forSpotlightIdentifier: "seedbox:mod:"))
        XCTAssertNil(SeedBoxSpotlightIndex.route(forSpotlightIdentifier: "not-an-identifier"))
    }
}
