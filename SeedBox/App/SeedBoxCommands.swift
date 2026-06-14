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
            commandButton(.createModSet)
        }

        CommandGroup(replacing: .importExport) {
            commandButton(.addMods)
            commandButton(.chooseModsFolder)
        }

        CommandGroup(replacing: .printItem) {}

        CommandGroup(replacing: .sidebar) {
            commandButton(.refreshModsFolder)
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
            commandButton(.showProblems)
            commandButton(.showActivity)
            commandButton(.showRestoreHistory)

            Divider()

            commandButton(.showModInspector)

            Divider()

            commandButton(.restorePreviousVersion)

            Divider()

            commandButton(.revealSelectedMod)
            commandButton(.revealModsFolder)
            commandButton(.revealArchivedModsFolder)
            commandButton(.pruneExpiredArchives)

            Divider()

            commandButton(.deleteSelectedMod)
        }

        CommandMenu(AppStrings.Commands.modSetMenu) {
            commandButton(.compareModSet)

            Divider()

            commandButton(.duplicateModSet)
            commandButton(.renameModSet)

            Divider()

            commandButton(.deleteModSet)
        }
    }

    private func commandButton(_ command: ModManagerCommand) -> some View {
        Button(role: command.role) {
            guard let context else {
                return
            }

            command.perform(with: context.actions)
        } label: {
            command.label(
                isShowingModInspector: context?.isShowingModInspector == true
            )
        }
        .modManagerKeyboardShortcut(command.shortcut)
        .disabled(!command.isEnabled(in: context))
    }
}
