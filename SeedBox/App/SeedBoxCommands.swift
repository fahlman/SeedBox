import AppKit
import SwiftUI

struct SeedBoxCommands: Commands {
    @FocusedValue(\.modManagerCommandContext) private var context
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            } label: {
                Label(AppStrings.Commands.aboutSeedBox, systemImage: "info.circle")
            }
        }

        CommandGroup(replacing: .newItem) {
            Button {
                context?.actions.createModSet()
            } label: {
                Label(AppStrings.Commands.newModSet, systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!canManageMods || context == nil)
        }

        CommandGroup(replacing: .importExport) {
            Button {
                context?.actions.addMods()
            } label: {
                Label(AppStrings.Commands.addMods, systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(!canManageMods || context == nil)

            Button {
                context?.actions.chooseModsFolder()
            } label: {
                Label(AppStrings.Commands.chooseModsFolder, systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(context == nil)
        }

        CommandGroup(replacing: .printItem) {}

        CommandGroup(replacing: .sidebar) {
            Button {
                context?.actions.refresh()
            } label: {
                Label(AppStrings.Commands.refreshModsFolder, systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!canManageMods || context == nil)
        }

        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .help) {
            Button {
                openWindow(id: "help")
            } label: {
                Label(AppStrings.Help.menuItem, systemImage: "questionmark.circle")
            }
            .keyboardShortcut("?", modifiers: [.command])

            Button {
                NSWorkspace.shared.open(HelpView.issuesURL)
            } label: {
                Label(AppStrings.Help.reportAProblem, systemImage: "exclamationmark.bubble")
            }
        }

        CommandMenu(AppStrings.Commands.modsMenu) {
            Button {
                context?.actions.showProblems()
            } label: {
                Label(AppStrings.Toolbar.problems, systemImage: "exclamationmark.triangle")
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
            .disabled(context == nil || !canShowProblems)

            Button {
                context?.actions.showActivity()
            } label: {
                Label(AppStrings.Toolbar.activity, systemImage: "clock")
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(context == nil || !canShowActivity)

            Button {
                context?.actions.showRestoreHistory()
            } label: {
                Label(AppStrings.Commands.restoreHistory, systemImage: "clock.arrow.circlepath")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(context == nil || !canShowRestoreHistory)

            Divider()

            Button {
                context?.actions.showModInspector()
            } label: {
                Label(modInspectorCommandTitle, systemImage: "info.circle")
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(context == nil || !canShowModInspector)

            Divider()

            Button {
                context?.actions.restorePreviousVersion()
            } label: {
                Label(AppStrings.Commands.restorePreviousVersion, systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!canManageMods || !canRestorePreviousVersion || context == nil)

            Divider()

            Button {
                context?.actions.revealSelectedMod()
            } label: {
                Label(AppStrings.Commands.revealSelectedModInFinder, systemImage: "eye")
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(context == nil || !canRevealSelectedMod)

            Button {
                context?.actions.revealModsFolder()
            } label: {
                Label(AppStrings.Commands.revealModsFolderInFinder, systemImage: "folder")
            }
            .disabled(!canManageMods)

            Button {
                context?.actions.revealArchivedModsFolder()
            } label: {
                Label(AppStrings.Commands.revealArchivedModsInFinder, systemImage: "archivebox")
            }
            .disabled(context == nil)

            Button {
                context?.actions.pruneExpiredArchives()
            } label: {
                Label(AppStrings.Commands.pruneExpiredArchives, systemImage: "archivebox")
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(context == nil || !canPruneExpiredArchives)

            Divider()

            Button(role: .destructive) {
                context?.actions.deleteSelectedMod()
            } label: {
                Label(AppStrings.Commands.deleteSelectedMod, systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(context == nil || !canDeleteSelectedMod)
        }

        CommandMenu(AppStrings.Commands.modSetMenu) {
            Button {
                context?.actions.compareSelectedModSet()
            } label: {
                Label(AppStrings.Commands.compareModSet, systemImage: "rectangle.split.2x1")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(!canManageMods || !canCompareSelectedModSet || context == nil)

            Divider()

            Button {
                context?.actions.duplicateSelectedModSet()
            } label: {
                Label(AppStrings.Commands.duplicateModSet, systemImage: "doc.on.doc")
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(!canManageMods || selection.selectedSet == nil || context == nil)

            Button {
                context?.actions.renameSelectedModSet()
            } label: {
                Label(AppStrings.Commands.renameModSet, systemImage: "pencil")
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canManageMods || !selection.selectedSetCanBeRenamed || context == nil)

            Divider()

            Button(role: .destructive) {
                context?.actions.deleteSelectedModSet()
            } label: {
                Label(AppStrings.Commands.deleteModSet, systemImage: "folder.badge.minus")
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
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

    private var canShowRestoreHistory: Bool {
        context?.canShowRestoreHistory ?? false
    }

    private var canShowModInspector: Bool {
        context?.canShowModInspector ?? false
    }

    private var modInspectorCommandTitle: String {
        context?.isShowingModInspector == true
            ? AppStrings.Toolbar.hideDetails
            : AppStrings.Commands.showModDetails
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
