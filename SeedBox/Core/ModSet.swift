import Foundation

struct ModSet: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var disabledFolderNames: [String]
    var isIncluded: Bool

    init(
        id: String,
        name: String,
        disabledFolderNames: [String],
        isIncluded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.disabledFolderNames = disabledFolderNames
        self.isIncluded = isIncluded
    }

    var disabledFolderTokens: Set<String> {
        Set(disabledFolderNames.map(\.normalizedFolderToken))
    }

    var isUserEditable: Bool {
        !isIncluded
    }

    var isUserRenamable: Bool {
        !isIncluded
    }

    var isUserDeletable: Bool {
        isUserRenamable
    }
}
