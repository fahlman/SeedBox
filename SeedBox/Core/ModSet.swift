import Foundation

struct ModSet: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var disabledFolderNames: [String]
    var isDefault: Bool

    init(
        id: String,
        name: String,
        disabledFolderNames: [String],
        isDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.disabledFolderNames = disabledFolderNames
        self.isDefault = isDefault
    }

    var disabledFolderTokens: Set<String> {
        Set(disabledFolderNames.map(\.normalizedFolderToken))
    }
}
