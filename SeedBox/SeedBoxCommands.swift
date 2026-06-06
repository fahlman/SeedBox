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
            Button(AppStrings.Toolbar.problems) {
                context?.showProblems()
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
            .disabled(context == nil || !canShowProblems)

            Button(AppStrings.Toolbar.activity) {
                context?.showActivity()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(context == nil || !canShowActivity)

            Divider()

            Button("Show Mod Details") {
                context?.showModInspector()
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(!canManageMods || context?.selectedMod == nil)

            Divider()

            Button("Restore Previous Version") {
                context?.restorePreviousVersion()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!canManageMods || !canRestorePreviousVersion || context == nil)

            Divider()

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

            Button("Prune Expired Archives") {
                context?.pruneExpiredArchives()
            }
            .disabled(context == nil || !canPruneExpiredArchives)

            Divider()

            Button("Delete Selected Mod", role: .destructive) {
                context?.deleteSelectedMod()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(!canManageMods || context?.selectedMod == nil)
        }

        CommandMenu("Mod Set") {
            Button("Compare Mod Set") {
                context?.compareSelectedModSet()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!canManageMods || !canCompareSelectedModSet || context == nil)

            Divider()

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

    private var canRestorePreviousVersion: Bool {
        context?.canRestorePreviousVersion ?? false
    }

    private var canCompareSelectedModSet: Bool {
        context?.canCompareSelectedModSet ?? false
    }

    private var canPruneExpiredArchives: Bool {
        context?.canPruneExpiredArchives ?? false
    }

    private var canShowProblems: Bool {
        context?.canShowProblems ?? false
    }

    private var canShowActivity: Bool {
        context?.canShowActivity ?? false
    }

    private var selection: ModSetSelectionState {
        context?.modSetSelection ?? ModSetSelectionState(
            sets: [],
            selectedSetID: ModSetStore.defaultSetID,
            appliedSetID: nil
        )
    }
}
