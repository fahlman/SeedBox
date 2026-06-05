import SwiftUI

struct ModManagerToolbar: ToolbarContent {
    @ObservedObject var viewModel: ModManagerViewModel
    var selectedMod: ModInfo?
    var selectModSet: (String) -> Void
    var createModSet: () -> Void
    var duplicateSelectedModSet: () -> Void
    var renameSelectedModSet: () -> Void
    var deleteSelectedModSet: () -> Void
    var addMods: () -> Void
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
            .disabled(selection.sets.isEmpty || !readiness.canManageMods)

            Button {
                createModSet()
            } label: {
                Label("New Mod Set", systemImage: "folder.badge.plus")
            }
            .labelStyle(.iconOnly)
            .help("New Mod Set")
            .disabled(!readiness.canManageMods)

            Button {
                duplicateSelectedModSet()
            } label: {
                Label("Duplicate Set", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .help("Duplicate Set")
            .disabled(selection.selectedSet == nil || !readiness.canManageMods)

            Button {
                renameSelectedModSet()
            } label: {
                Label("Rename Set", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .help("Rename Set")
            .disabled(!selection.selectedSetCanBeRenamed || !readiness.canManageMods)

            Button(role: .destructive) {
                deleteSelectedModSet()
            } label: {
                Label("Delete Set", systemImage: "folder.badge.minus")
            }
            .labelStyle(.iconOnly)
            .help("Delete Set")
            .disabled(!selection.selectedSetCanBeDeleted || !readiness.canManageMods)
        }

        ToolbarItemGroup {
            Button {
                addMods()
            } label: {
                Label("Add Mods", systemImage: "square.and.arrow.down")
            }
            .disabled(!readiness.canManageMods)

            Button {
                revealSelectedMod()
            } label: {
                Label("Reveal in Finder", systemImage: "eye")
            }
            .disabled(selectedMod == nil || !readiness.canManageMods)

            Button(role: .destructive) {
                deleteSelectedMod()
            } label: {
                Label("Delete Mod", systemImage: "trash")
            }
            .disabled(selectedMod == nil || !readiness.canManageMods)

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private var readiness: ModManagerReadiness {
        viewModel.state.readiness
    }

    private var selection: ModSetSelectionState {
        viewModel.state.modSetSelection
    }
}
