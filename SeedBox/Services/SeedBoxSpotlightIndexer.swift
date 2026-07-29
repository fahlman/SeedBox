@preconcurrency import CoreSpotlight
import Foundation

@MainActor
protocol SeedBoxSearchIndexing: AnyObject {
    func deleteSeedBoxItems() async throws
    func index(_ entities: [SeedBoxEntity]) async throws
}

@MainActor
final class CoreSpotlightSearchIndex: SeedBoxSearchIndexing {
    private let index: CSSearchableIndex

    init(index: CSSearchableIndex = .default()) {
        self.index = index
    }

    func deleteSeedBoxItems() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            index.deleteSearchableItems(
                withDomainIdentifiers: [SeedBoxSpotlightIndex.domainIdentifier]
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func index(_ entities: [SeedBoxEntity]) async throws {
        let items = SeedBoxSpotlightIndex.searchableItems(for: entities)
        guard !items.isEmpty else {
            return
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            index.indexSearchableItems(items) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// Keeps the Core Spotlight index in sync with the local library.
///
/// Requests are coalesced and executed serially. This matters because a full
/// refresh has two asynchronous phases (delete, then index); allowing refreshes
/// to overlap can let an older delete erase a newer index.
@MainActor
final class SeedBoxSpotlightIndexer {
    static let shared = SeedBoxSpotlightIndexer()

    private enum Request {
        case replace([SeedBoxEntity])
        case clear
    }

    private let searchIndex: any SeedBoxSearchIndexing
    private var pendingRequest: Request?
    private var worker: Task<Void, Never>?

    init(searchIndex: any SeedBoxSearchIndexing = CoreSpotlightSearchIndex()) {
        self.searchIndex = searchIndex
    }

    static func reindex(from state: ModManagerState) {
        guard state.hasSavedFolderAccess else {
            shared.enqueue(.clear)
            return
        }

        shared.enqueue(
            .replace(
                SeedBoxEntityCatalog.entities(from: state, on: .spotlight)
            )
        )
    }

    static func clear() {
        shared.enqueue(.clear)
    }

    func reindex(_ entities: [SeedBoxEntity]) {
        enqueue(.replace(entities))
    }

    func clear() {
        enqueue(.clear)
    }

    func waitUntilIdle() async {
        while let worker {
            await worker.value
        }
    }

    private func enqueue(_ request: Request) {
        pendingRequest = request
        guard worker == nil else {
            return
        }

        worker = Task { [weak self] in
            await self?.drainRequests()
        }
    }

    private func drainRequests() async {
        while let request = pendingRequest {
            pendingRequest = nil

            do {
                try await searchIndex.deleteSeedBoxItems()
            } catch {
                AppLog.spotlight.error("Could not clear the Seed Box Spotlight index: \(error)")
                continue
            }

            // A newer snapshot arrived while deletion was running. Skip
            // indexing the obsolete one and immediately process the latest.
            guard pendingRequest == nil else {
                continue
            }

            guard case .replace(let entities) = request, !entities.isEmpty else {
                continue
            }

            do {
                try await searchIndex.index(entities)
            } catch {
                AppLog.spotlight.error("Could not update the Seed Box Spotlight index: \(error)")
            }
        }

        worker = nil
    }
}
