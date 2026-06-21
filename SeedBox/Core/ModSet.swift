import Foundation

struct ModSet: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var disabledFolderNames: [String]
    var isEditable: Bool

    init(
        id: String,
        name: String,
        disabledFolderNames: [String],
        isEditable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.disabledFolderNames = disabledFolderNames
        self.isEditable = isEditable
    }

    var disabledFolderTokens: Set<String> {
        Set(disabledFolderNames.map(\.normalizedFolderToken))
    }

    var isUserEditable: Bool {
        isEditable
    }

    var isUserRenamable: Bool {
        isEditable
    }

    var isUserDeletable: Bool {
        isEditable
    }
}
