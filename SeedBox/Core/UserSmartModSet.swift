import Foundation

struct UserSmartModSet: Codable, Equatable, Identifiable, Sendable {
    static let defaultSystemImageName = "line.3.horizontal.decrease.circle"

    var id: String
    var name: String
    var searchText: String
    var systemImageName: String

    init(
        id: String = UUID().uuidString,
        name: String,
        searchText: String,
        systemImageName: String = Self.defaultSystemImageName
    ) {
        self.id = id
        self.name = name
        self.searchText = searchText
        self.systemImageName = systemImageName
    }
}
