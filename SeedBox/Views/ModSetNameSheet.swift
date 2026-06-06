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
}

struct ModSetNameSheet: View {
    var mode: ModSetEditorMode
    var onCancel: () -> Void
    var onCommit: (String) -> Void

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(
        mode: ModSetEditorMode,
        onCancel: @escaping () -> Void,
        onCommit: @escaping (String) -> Void
    ) {
        self.mode = mode
        self.onCancel = onCancel
        self.onCommit = onCommit
        _name = State(initialValue: mode.initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.headline)

            TextField("Name", text: $name)
                .focused($isNameFocused)
                .onSubmit(commit)

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

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        guard !trimmedName.isEmpty else {
            return
        }

        onCommit(trimmedName)
    }
}
