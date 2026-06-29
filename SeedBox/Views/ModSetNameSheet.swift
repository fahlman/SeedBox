import SwiftUI

enum ModSetEditorMode: Identifiable {
    case create
    case duplicate(ModSet)
    case rename(ModSet)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .duplicate(let set):
            return "duplicate-\(set.id)"
        case .rename(let set):
            return "rename-\(set.id)"
        }
    }

    var title: String {
        switch self {
        case .create:
            return AppStrings.ModSetEditor.createTitle
        case .duplicate:
            return AppStrings.ModSetEditor.duplicateTitle
        case .rename:
            return AppStrings.ModSetEditor.renameTitle
        }
    }

    var actionTitle: String {
        switch self {
        case .create:
            return AppStrings.ModSetEditor.createAction
        case .duplicate:
            return AppStrings.ModSetEditor.duplicateAction
        case .rename:
            return AppStrings.ModSetEditor.renameAction
        }
    }

    var initialName: String {
        switch self {
        case .create:
            return AppStrings.ModSetNames.newSet
        case .duplicate(let set):
            return AppStrings.ModSetNames.copiedSetName(set.name)
        case .rename(let set):
            return set.name
        }
    }

    /// Whether the editor should offer a base (parent) Mod Set picker. Renaming
    /// only changes the name, so it keeps the existing base implicitly.
    var supportsBaseSelection: Bool {
        switch self {
        case .create, .duplicate:
            return true
        case .rename:
            return false
        }
    }

    /// The base set pre-selected when the editor opens. Duplicating preserves
    /// the source set's base so the copy inherits the same way.
    var initialParentID: String? {
        switch self {
        case .create, .rename:
            return nil
        case .duplicate(let set):
            return set.parentID
        }
    }

    /// The set being edited, used to exclude it (and its descendants) from the
    /// base picker so a set cannot inherit from itself.
    var editingSetID: String? {
        switch self {
        case .create:
            return nil
        case .duplicate(let set), .rename(let set):
            return set.id
        }
    }
}

struct ModSetNameSheet: View {
    var mode: ModSetEditorMode
    var availableBaseSets: [ModSet]
    var onCancel: () -> Void
    var onCommit: (String, String?) -> Void

    @State private var name: String
    @State private var selectedParentID: String?
    @FocusState private var isNameFocused: Bool

    init(
        mode: ModSetEditorMode,
        availableBaseSets: [ModSet] = [],
        onCancel: @escaping () -> Void,
        onCommit: @escaping (String, String?) -> Void
    ) {
        self.mode = mode
        self.availableBaseSets = availableBaseSets
        self.onCancel = onCancel
        self.onCommit = onCommit
        _name = State(initialValue: mode.initialName)
        _selectedParentID = State(initialValue: mode.initialParentID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.headline)

            TextField("Name", text: $name)
                .focused($isNameFocused)
                .onSubmit(commit)

            if showsBaseSelection {
                Picker(AppStrings.ModSetEditor.baseSet, selection: $selectedParentID) {
                    Text(AppStrings.ModSetEditor.noBaseSet)
                        .tag(String?.none)
                    ForEach(availableBaseSets) { set in
                        Text(set.name)
                            .tag(String?.some(set.id))
                    }
                }
            }

            HStack {
                Spacer()

                Button(AppStrings.Common.cancel, role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(mode.actionTitle) {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            isNameFocused = true
        }
    }

    private var showsBaseSelection: Bool {
        mode.supportsBaseSelection && !availableBaseSets.isEmpty
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        guard !trimmedName.isEmpty else {
            return
        }

        let parentID = mode.supportsBaseSelection ? selectedParentID : mode.initialParentID
        onCommit(trimmedName, parentID)
    }
}
