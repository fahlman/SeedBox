import SwiftUI

struct ModManagerToolbar: ToolbarContent {
    var presentationState: ModManagerPresentationState
    var isShowingModInspector: Bool
    var actions: ModManagerActions

    var body: some ToolbarContent {
        ToolbarItemGroup {
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

    private func toolbarButton(
        _ command: ModManagerCommand,
        showsTitle: Bool = false
    ) -> some View {
        Button(role: command.role) {
            command.perform(with: actions)
        } label: {
            command.label(
                isShowingModInspector: isShowingModInspector
            )
        }
        .modManagerToolbarLabelStyle(showsTitle: showsTitle)
        .help(command.title(
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
