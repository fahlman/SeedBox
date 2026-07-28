import CoreSpotlight
import XCTest
@testable import SeedBox

final class SeedBoxSpotlightIndexTests: SeedBoxTestCase {
    func testRendersEntitiesAsSearchableItems() throws {
        let entity = SeedBoxEntity(
            kind: .mod,
            rawIdentifier: "abc#contentpatcher",
            title: "Content Patcher",
            subtitle: "Content • Version 2.0.0",
            symbolName: "puzzlepiece.extension",
            keywords: ["Pathoschild", "2.0.0"],
            route: .mod(id: "abc#contentpatcher"),
            surfaces: [.spotlight]
        )

        let item = try XCTUnwrap(SeedBoxSpotlightIndex.searchableItems(for: [entity]).first)

        XCTAssertEqual(item.uniqueIdentifier, "seedbox:mod:abc#contentpatcher")
        XCTAssertEqual(item.domainIdentifier, SeedBoxSpotlightIndex.domainIdentifier)
        XCTAssertEqual(item.attributeSet.title, "Content Patcher")
        XCTAssertEqual(item.attributeSet.contentDescription, "Content • Version 2.0.0")
        XCTAssertEqual(item.attributeSet.keywords, ["Pathoschild", "2.0.0"])
    }
}
