import SwiftUI

struct SeedBoxCommands: Commands {
    @FocusedValue(\.modManagerCommandContext) private var context

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(AppStrings.Commands.newModSet) {
                context?.actions.createModSet()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!canManageMods || context == nil)
        }

        CommandGroup(replacing: .importExport) {
            Button(AppStrings.Commands.addMods) {
                context?.actions.addMods()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(!canManageMods || context == nil)

            Button(AppStrings.Commands.chooseModsFolder) {
                context?.actions.chooseModsFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(context == nil)
        }

        CommandGroup(replacing: .printItem) {}

        CommandGroup(replacing: .sidebar) {
            Button(AppStrings.Commands.refreshModsFolder) {
                context?.actions.refresh()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!canManageMods || context == nil)
        }

        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .help) {}

        CommandMenu(AppStrings.Commands.modsMenu) {
            Button(AppStrings.Toolbar.problems) {
                context?.actions.showProblems()
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
            .disabled(context == nil || !canShowProblems)

            Button(AppStrings.Toolbar.activity) {
                context?.actions.showActivity()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(context == nil || !canShowActivity)

            Divider()

            Button(AppStrings.Commands.showModDetails) {
                context?.actions.showModInspector()
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(context == nil || !canShowModInspector)

            Divider()

            Button(AppStrings.Commands.restorePreviousVersion) {
                context?.actions.restorePreviousVersion()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!canManageMods || !canRestorePreviousVersion || context == nil)

            Divider()

            Button(AppStrings.Commands.revealSelectedModInFinder) {
                context?.actions.revealSelectedMod()
            }
            .disabled(context == nil || !canRevealSelectedMod)

            Button(AppStrings.Commands.revealModsFolderInFinder) {
                context?.actions.revealModsFolder()
            }
            .disabled(!canManageMods)

            Button(AppStrings.Commands.revealArchivedModsInFinder) {
                context?.actions.revealArchivedModsFolder()
            }
            .disabled(context == nil)

            Button(AppStrings.Commands.pruneExpiredArchives) {
                context?.actions.pruneExpiredArchives()
            }
            .disabled(context == nil || !canPruneExpiredArchives)

            Divider()

            Button(AppStrings.Commands.deleteSelectedMod, role: .destructive) {
                context?.actions.deleteSelectedMod()
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(context == nil || !canDeleteSelectedMod)
        }

        CommandMenu(AppStrings.Commands.modSetMenu) {
            Button(AppStrings.Commands.compareModSet) {
                context?.actions.compareSelectedModSet()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!canManageMods || !canCompareSelectedModSet || context == nil)

            Divider()

            Button(AppStrings.Commands.duplicateModSet) {
                context?.actions.duplicateSelectedModSet()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!canManageMods || selection.selectedSet == nil || context == nil)

            Button(AppStrings.Commands.renameModSet) {
                context?.actions.renameSelectedModSet()
            }
            .disabled(!canManageMods || !selection.selectedSetCanBeRenamed || context == nil)

            Divider()

            Button(AppStrings.Commands.deleteModSet, role: .destructive) {
                context?.actions.deleteSelectedModSet()
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

    private var canShowModInspector: Bool {
        context?.canShowModInspector ?? false
    }

    private var canRevealSelectedMod: Bool {
        context?.canRevealSelectedMod ?? false
    }

    private var canDeleteSelectedMod: Bool {
        context?.canDeleteSelectedMod ?? false
    }

    private var selection: ModSetSelectionState {
        context?.modSetSelection ?? ModSetSelectionState(
            sets: [],
            selectedSetID: ModSetStore.defaultSetID,
            appliedSetID: nil
        )
    }
}
