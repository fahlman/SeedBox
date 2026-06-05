import SwiftUI

struct SeedBoxCommands: Commands {
    @FocusedValue(\.modManagerCommandContext) private var context

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Mod Set") {
                context?.createModSet()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!canManageMods || context == nil)
        }

        CommandGroup(replacing: .importExport) {
            Button("Add Mods...") {
                context?.addMods()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(!canManageMods || context == nil)

            Button("Choose Mods Folder...") {
                context?.chooseModsFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(context == nil)
        }

        CommandGroup(replacing: .printItem) {}

        CommandGroup(replacing: .sidebar) {
            Button("Refresh Mods Folder") {
                context?.refresh()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!canManageMods || context == nil)
        }

        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .help) {}

        CommandMenu("Mods") {
            Button("Reveal Selected Mod in Finder") {
                context?.revealSelectedMod()
            }
            .disabled(!canManageMods || context?.selectedMod == nil)

            Button("Reveal Mods Folder in Finder") {
                context?.revealModsFolder()
            }
            .disabled(!canManageMods)

            Button("Reveal Archived Mods in Finder") {
                context?.revealArchivedModsFolder()
            }
            .disabled(context == nil)

            Divider()

            Button("Delete Selected Mod", role: .destructive) {
                context?.deleteSelectedMod()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(!canManageMods || context?.selectedMod == nil)
        }

        CommandMenu("Mod Set") {
            Button("Duplicate Mod Set") {
                context?.duplicateSelectedModSet()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!canManageMods || selection.selectedSet == nil || context == nil)

            Button("Rename Mod Set") {
                context?.renameSelectedModSet()
            }
            .disabled(!canManageMods || !selection.selectedSetCanBeRenamed || context == nil)

            Divider()

            Button("Delete Mod Set", role: .destructive) {
                context?.deleteSelectedModSet()
            }
            .disabled(!canManageMods || !selection.selectedSetCanBeDeleted || context == nil)
        }
    }

    private var canManageMods: Bool {
        context?.canManageMods ?? false
    }

    private var selection: ModSetSelectionState {
        context?.modSetSelection ?? ModSetSelectionState(
            sets: [],
            selectedSetID: ModSetStore.defaultSetID,
            appliedSetID: nil
        )
    }
}
