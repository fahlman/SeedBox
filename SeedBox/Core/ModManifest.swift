import Foundation

struct ModManifest: Codable, Equatable, Sendable {
    struct ContentPackFor: Codable, Equatable, Sendable {
        var uniqueID: String?

        private enum CodingKeys: String, CodingKey {
            case uniqueID = "UniqueID"
        }
    }

    struct Dependency: Codable, Equatable, Sendable {
        var uniqueID: String?
        var isRequired: Bool?

        private enum CodingKeys: String, CodingKey {
            case uniqueID = "UniqueID"
            case isRequired = "IsRequired"
        }
    }

    var name: String?
    var author: String?
    var version: String?
    var description: String?
    var uniqueID: String?
    var contentPackFor: ContentPackFor?
    var dependencies: [Dependency]?

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case author = "Author"
        case version = "Version"
        case description = "Description"
        case uniqueID = "UniqueID"
        case contentPackFor = "ContentPackFor"
        case dependencies = "Dependencies"
    }
}
