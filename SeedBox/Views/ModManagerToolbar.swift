import SwiftUI

struct ModManagerToolbar: ToolbarContent {
    @ObservedObject var viewModel: ModManagerViewModel
    var selectedMod: ModInfo?
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
                    Task {
                        await viewModel.selectModSet(id: selectedID)
                    }
                }
            )) {
                ForEach(selection.sets) { set in
                    Text(set.name)
                        .tag(set.id)
                }
            }
            .frame(width: 220)
            .disabled(selection.sets.isEmpty || !readiness.canManageMods)

            Button {
                createModSet()
            } label: {
                Label("New Mod Set", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .help("New Mod Set")
            .disabled(!readiness.canManageMods)

            Menu {
                Button {
                    duplicateSelectedModSet()
                } label: {
                    Label("Duplicate Set", systemImage: "doc.on.doc")
                }
                .disabled(selection.selectedSet == nil || !readiness.canManageMods)

                Button {
                    renameSelectedModSet()
                } label: {
                    Label("Rename Set", systemImage: "pencil")
                }
                .disabled(!selection.selectedSetCanBeRenamed || !readiness.canManageMods)

                Divider()

                Button(role: .destructive) {
                    deleteSelectedModSet()
                } label: {
                    Label("Delete Set", systemImage: "trash")
                }
                .disabled(!selection.selectedSetCanBeDeleted || !readiness.canManageMods)
            } label: {
                Label("Set Actions", systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
            .disabled(!readiness.canManageMods)
        }

        ToolbarItemGroup {
            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
                addMods()
            } label: {
                Label("Add Mods", systemImage: "plus")
            }
            .disabled(!readiness.canManageMods)

            Button {
                revealSelectedMod()
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
            }
            .disabled(selectedMod == nil || !readiness.canManageMods)

            Button(role: .destructive) {
                deleteSelectedMod()
            } label: {
                Label("Move to Trash", systemImage: "trash")
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
