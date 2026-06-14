import SwiftUI

struct ModManagerToolbar: ToolbarContent {
    var presentationState: ModManagerPresentationState
    var isShowingModInspector: Bool
    var selectModSet: (String) -> Void
    var actions: ModManagerActions

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Picker(AppStrings.Toolbar.modSet, selection: Binding(
                get: { selection.selectedSetID },
                set: { selectedID in
                    selectModSet(selectedID)
                }
            )) {
                ForEach(selection.sets) { set in
                    Text(set.name)
                        .tag(set.id)
                }
            }
            .pickerStyle(.menu)
            .help(AppStrings.Toolbar.modSet)
            .disabled(selection.sets.isEmpty || !presentationState.canManageMods)

            toolbarButton(.createModSet)
            toolbarButton(.duplicateModSet)
            toolbarButton(.renameModSet)
            toolbarButton(.deleteModSet)
            toolbarButton(.compareModSet)
        }

        ToolbarItemGroup {
            toolbarButton(.showProblems)
            toolbarButton(.showActivity)
            toolbarButton(.showRestoreHistory)
            toolbarButton(.addMods, showsTitle: true)
            toolbarButton(.restorePreviousVersion)
            toolbarButton(.showModInspector)
            toolbarButton(.revealSelectedMod, showsTitle: true)
            toolbarButton(.deleteSelectedMod, showsTitle: true)
            toolbarButton(.pruneExpiredArchives)

            SettingsLink {
                Label(AppStrings.Toolbar.settings, systemImage: "gearshape")
            }
        }
    }

    private var selection: ModSetSelectionState {
        presentationState.modSetSelection
    }

    private func toolbarButton(
        _ command: ModManagerCommand,
        showsTitle: Bool = false
    ) -> some View {
        Button(role: command.role) {
            command.perform(with: actions)
        } label: {
            command.label(
                for: .toolbar,
                isShowingModInspector: isShowingModInspector
            )
        }
        .modManagerToolbarLabelStyle(showsTitle: showsTitle)
        .help(command.title(
            for: .toolbar,
            isShowingModInspector: isShowingModInspector
        ))
        .disabled(!command.isEnabled(in: presentationState))
    }
}

private extension View {
    @ViewBuilder
    func modManagerToolbarLabelStyle(showsTitle: Bool) -> some View {
        if showsTitle {
            self
        } else {
            labelStyle(.iconOnly)
        }
    }
}
