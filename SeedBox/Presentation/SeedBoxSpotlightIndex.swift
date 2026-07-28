import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Turns shared ``SeedBoxEntity`` values into Core Spotlight items.
///
/// Identity and route mapping live in ``SeedBoxEntityCatalog`` so Spotlight,
/// Shortcuts, and routing all agree; this type only renders an entity as a
/// searchable item with safe attributes.
enum SeedBoxSpotlightIndex {
    static let domainIdentifier = "com.fahlsing.seedbox.library"

    static func searchableItems(for entities: [SeedBoxEntity]) -> [CSSearchableItem] {
        entities.map(makeItem)
    }

    private static func makeItem(_ entity: SeedBoxEntity) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = entity.title
        attributes.displayName = entity.title
        attributes.contentDescription = entity.subtitle
        if !entity.keywords.isEmpty {
            attributes.keywords = entity.keywords
        }

        return CSSearchableItem(
            uniqueIdentifier: entity.systemIdentifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }
}
