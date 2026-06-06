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

            Button {
                actions.createModSet()
            } label: {
                Label(AppStrings.Toolbar.newModSet, systemImage: "folder.badge.plus")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.newModSet)
            .disabled(!presentationState.canManageMods)

            Button {
                actions.duplicateSelectedModSet()
            } label: {
                Label(AppStrings.Toolbar.duplicateSet, systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.duplicateSet)
            .disabled(selection.selectedSet == nil || !presentationState.canManageMods)

            Button {
                actions.renameSelectedModSet()
            } label: {
                Label(AppStrings.Toolbar.renameSet, systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.renameSet)
            .disabled(!selection.selectedSetCanBeRenamed || !presentationState.canManageMods)

            Button(role: .destructive) {
                actions.deleteSelectedModSet()
            } label: {
                Label(AppStrings.Toolbar.deleteSet, systemImage: "folder.badge.minus")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.deleteSet)
            .disabled(!selection.selectedSetCanBeDeleted || !presentationState.canManageMods)

            Button {
                actions.compareSelectedModSet()
            } label: {
                Label(AppStrings.Toolbar.compareModSet, systemImage: "rectangle.split.2x1")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.compareModSet)
            .disabled(!presentationState.canCompareSelectedModSet)
        }

        ToolbarItemGroup {
            Button {
                actions.showProblems()
            } label: {
                Label(AppStrings.Toolbar.problems, systemImage: "exclamationmark.triangle")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.problems)
            .disabled(!presentationState.canShowProblems)

            Button {
                actions.showActivity()
            } label: {
                Label(AppStrings.Toolbar.activity, systemImage: "clock")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.activity)
            .disabled(!presentationState.canShowActivity)

            Button {
                actions.addMods()
            } label: {
                Label(AppStrings.Toolbar.addMods, systemImage: "square.and.arrow.down")
            }
            .disabled(!presentationState.canManageMods)

            Button {
                actions.restorePreviousVersion()
            } label: {
                Label(AppStrings.Toolbar.restorePreviousVersion, systemImage: "arrow.uturn.backward")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.restorePreviousVersion)
            .disabled(!presentationState.canRestorePreviousVersion)

            Button {
                actions.showModInspector()
            } label: {
                Label(isShowingModInspector ? AppStrings.Toolbar.hideDetails : AppStrings.Toolbar.showDetails, systemImage: "info.circle")
            }
            .labelStyle(.iconOnly)
            .help(isShowingModInspector ? AppStrings.Toolbar.hideDetails : AppStrings.Toolbar.showDetails)
            .disabled(!presentationState.canShowModInspector)

            Button {
                actions.revealSelectedMod()
            } label: {
                Label(AppStrings.Toolbar.revealInFinder, systemImage: "eye")
            }
            .disabled(!presentationState.canRevealSelectedMod)

            Button(role: .destructive) {
                actions.deleteSelectedMod()
            } label: {
                Label(AppStrings.Toolbar.deleteMod, systemImage: "trash")
            }
            .disabled(!presentationState.canDeleteSelectedMod)

            Button {
                actions.pruneExpiredArchives()
            } label: {
                Label(AppStrings.Toolbar.pruneExpiredArchives, systemImage: "archivebox")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.pruneExpiredArchives)
            .disabled(!presentationState.canPruneExpiredArchives)

            SettingsLink {
                Label(AppStrings.Toolbar.settings, systemImage: "gearshape")
            }
        }
    }

    private var selection: ModSetSelectionState {
        presentationState.modSetSelection
    }
}
