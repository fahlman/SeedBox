import CoreSpotlight
import Foundation

/// Keeps the Core Spotlight index in sync with the local library.
///
/// Indexing is a full replace within Seed Box's domain: the previous items are
/// removed and the current ones re-indexed, so deleting a mod or set removes its
/// Spotlight result and stable identifiers never produce duplicates. Indexing
/// only runs once the user has a real local model (a chosen Mods folder).
enum SeedBoxSpotlightIndexer {
    static func reindex(from state: ModManagerState) {
        guard state.hasSavedFolderAccess else {
            return
        }

        let items = SeedBoxSpotlightIndex.searchableItems(
            mods: state.mods,
            modSets: state.modSets,
            userSmartModSets: state.userSmartModSets
        )

        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [SeedBoxSpotlightIndex.domainIdentifier]) { _ in
            guard !items.isEmpty else {
                return
            }
            index.indexSearchableItems(items)
        }
    }

    static func clear() {
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [SeedBoxSpotlightIndex.domainIdentifier])
    }
}
