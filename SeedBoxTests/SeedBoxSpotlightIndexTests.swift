import CoreSpotlight
import XCTest
@testable import SeedBox

@MainActor
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

    func testNewerRequestSupersedesSnapshotWaitingForDeletion() async {
        let searchIndex = ControlledSearchIndex()
        let indexer = SeedBoxSpotlightIndexer(searchIndex: searchIndex)
        let oldEntity = makeEntity(id: "old", title: "Old")
        let newEntity = makeEntity(id: "new", title: "New")

        indexer.reindex([oldEntity])
        await searchIndex.waitForDeleteCount(1)
        indexer.reindex([newEntity])
        searchIndex.releaseFirstDelete()
        await indexer.waitUntilIdle()

        XCTAssertEqual(searchIndex.deleteCount, 2)
        XCTAssertEqual(searchIndex.indexedEntityIDs, [["seedbox:mod:new"]])
    }

    private func makeEntity(id: String, title: String) -> SeedBoxEntity {
        SeedBoxEntity(
            kind: .mod,
            rawIdentifier: id,
            title: title,
            subtitle: nil,
            symbolName: "puzzlepiece.extension",
            keywords: [],
            route: .mod(id: id),
            surfaces: [.spotlight]
        )
    }
}

@MainActor
private final class ControlledSearchIndex: SeedBoxSearchIndexing {
    private(set) var deleteCount = 0
    private(set) var indexedEntityIDs: [[String]] = []
    private var firstDeleteContinuation: CheckedContinuation<Void, Never>?

    func deleteSeedBoxItems() async throws {
        deleteCount += 1
        guard deleteCount == 1 else {
            return
        }

        await withCheckedContinuation { continuation in
            firstDeleteContinuation = continuation
        }
    }

    func index(_ entities: [SeedBoxEntity]) async throws {
        indexedEntityIDs.append(entities.map(\.systemIdentifier))
    }

    func waitForDeleteCount(_ expectedCount: Int) async {
        while deleteCount < expectedCount {
            await Task.yield()
        }
    }

    func releaseFirstDelete() {
        firstDeleteContinuation?.resume()
        firstDeleteContinuation = nil
    }
}
