import Foundation

struct ModSet: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var disabledFolderNames: [String]
    var isDefault: Bool
    var isIncluded: Bool

    init(
        id: String,
        name: String,
        disabledFolderNames: [String],
        isDefault: Bool,
        isIncluded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.disabledFolderNames = disabledFolderNames
        self.isDefault = isDefault
        self.isIncluded = isIncluded
    }

    var disabledFolderTokens: Set<String> {
        Set(disabledFolderNames.map(\.normalizedFolderToken))
    }

    var isUserEditable: Bool {
        !isIncluded
    }
}
