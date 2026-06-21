import Foundation

struct ModSet: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var disabledFolderNames: [String]

    init(
        id: String,
        name: String,
        disabledFolderNames: [String]
    ) {
        self.id = id
        self.name = name
        self.disabledFolderNames = disabledFolderNames
    }

    var disabledFolderTokens: Set<String> {
        Set(disabledFolderNames.map(\.normalizedFolderToken))
    }

    var isUserEditable: Bool {
        true
    }

    var isUserRenamable: Bool {
        true
    }

    var isUserDeletable: Bool {
        true
    }
}
