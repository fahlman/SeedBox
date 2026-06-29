import Foundation

struct ModSet: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var disabledFolderNames: [String]
    var isEditable: Bool

    /// Optional reference to another Mod Set this set inherits from.
    ///
    /// When set, this set layers its own choices on top of the resolved
    /// parent: it starts from the parent's enabled/disabled state, then
    /// applies its own `disabledFolderNames` (additionally disabled) and
    /// `enabledFolderNames` (explicitly re-enabled) on top. See
    /// ``ModSetResolver`` for the full resolution rules, including how
    /// cycles and missing parents are handled.
    var parentID: String?

    /// Folders this set explicitly re-enables, overriding a parent that
    /// disabled them. Ignored for sets without a `parentID`.
    var enabledFolderNames: [String]

    init(
        id: String,
        name: String,
        disabledFolderNames: [String],
        isEditable: Bool = true,
        parentID: String? = nil,
        enabledFolderNames: [String] = []
    ) {
        self.id = id
        self.name = name
        self.disabledFolderNames = disabledFolderNames
        self.isEditable = isEditable
        self.parentID = parentID
        self.enabledFolderNames = enabledFolderNames
    }

    var disabledFolderTokens: Set<String> {
        Set(disabledFolderNames.map(\.normalizedFolderToken))
    }

    /// Tokens this set explicitly re-enables relative to its parent.
    var enabledFolderTokens: Set<String> {
        Set(enabledFolderNames.map(\.normalizedFolderToken))
    }

    /// Whether this set declares a parent to inherit from.
    var hasParent: Bool {
        parentID != nil
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
