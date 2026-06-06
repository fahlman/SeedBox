import SwiftUI

struct ModManagerToolbar: ToolbarContent {
    var presentationState: ModManagerPresentationState
    var isShowingModInspector: Bool
    var selectModSet: (String) -> Void
    var showProblems: () -> Void
    var showActivity: () -> Void
    var showModInspector: () -> Void
    var createModSet: () -> Void
    var duplicateSelectedModSet: () -> Void
    var renameSelectedModSet: () -> Void
    var deleteSelectedModSet: () -> Void
    var compareSelectedModSet: () -> Void
    var addMods: () -> Void
    var pruneExpiredArchives: () -> Void
    var restorePreviousVersion: () -> Void
    var revealSelectedMod: () -> Void
    var deleteSelectedMod: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Mod Set", selection: Binding(
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
            .help("Mod Set")
            .disabled(selection.sets.isEmpty || !presentationState.canManageMods)

            Button {
                createModSet()
            } label: {
                Label("New Mod Set", systemImage: "folder.badge.plus")
            }
            .labelStyle(.iconOnly)
            .help("New Mod Set")
            .disabled(!presentationState.canManageMods)

            Button {
                duplicateSelectedModSet()
            } label: {
                Label("Duplicate Set", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .help("Duplicate Set")
            .disabled(selection.selectedSet == nil || !presentationState.canManageMods)

            Button {
                renameSelectedModSet()
            } label: {
                Label("Rename Set", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .help("Rename Set")
            .disabled(!selection.selectedSetCanBeRenamed || !presentationState.canManageMods)

            Button(role: .destructive) {
                deleteSelectedModSet()
            } label: {
                Label("Delete Set", systemImage: "folder.badge.minus")
            }
            .labelStyle(.iconOnly)
            .help("Delete Set")
            .disabled(!selection.selectedSetCanBeDeleted || !presentationState.canManageMods)

            Button {
                compareSelectedModSet()
            } label: {
                Label("Compare Mod Set", systemImage: "rectangle.split.2x1")
            }
            .labelStyle(.iconOnly)
            .help("Compare Mod Set")
            .disabled(!presentationState.canCompareSelectedModSet)
        }

        ToolbarItemGroup {
            Button {
                showProblems()
            } label: {
                Label(AppStrings.Toolbar.problems, systemImage: "exclamationmark.triangle")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.problems)
            .disabled(!presentationState.canShowProblems)

            Button {
                showActivity()
            } label: {
                Label(AppStrings.Toolbar.activity, systemImage: "clock")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.activity)
            .disabled(!presentationState.canShowActivity)

            Button {
                addMods()
            } label: {
                Label(AppStrings.Toolbar.addMods, systemImage: "square.and.arrow.down")
            }
            .disabled(!presentationState.canManageMods)

            Button {
                restorePreviousVersion()
            } label: {
                Label(AppStrings.Toolbar.restorePreviousVersion, systemImage: "arrow.uturn.backward")
            }
            .labelStyle(.iconOnly)
            .help(AppStrings.Toolbar.restorePreviousVersion)
            .disabled(!presentationState.canRestorePreviousVersion)

            Button {
                showModInspector()
            } label: {
                Label(isShowingModInspector ? AppStrings.Toolbar.hideDetails : AppStrings.Toolbar.showDetails, systemImage: "info.circle")
            }
            .labelStyle(.iconOnly)
            .help(isShowingModInspector ? AppStrings.Toolbar.hideDetails : AppStrings.Toolbar.showDetails)
            .disabled(!presentationState.canShowModInspector)

            Button {
                revealSelectedMod()
            } label: {
                Label(AppStrings.Toolbar.revealInFinder, systemImage: "eye")
            }
            .disabled(!presentationState.canRevealSelectedMod)

            Button(role: .destructive) {
                deleteSelectedMod()
            } label: {
                Label(AppStrings.Toolbar.deleteMod, systemImage: "trash")
            }
            .disabled(!presentationState.canDeleteSelectedMod)

            Button {
                pruneExpiredArchives()
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
