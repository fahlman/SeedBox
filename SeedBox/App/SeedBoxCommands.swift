import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SeedBoxCommands: Commands {
    @FocusedValue(\.modManagerCommandContext) private var context
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                NSApplication.shared.orderFrontStandardAboutPanel(options: AboutPanelContent.options())
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

            Divider()

            Button {
                importModSetFromPanel()
            } label: {
                Label(AppStrings.Commands.importModSet, systemImage: "square.and.arrow.down")
            }

            Button {
                exportSelectedModSetToPanel()
            } label: {
                Label(AppStrings.Commands.exportModSet, systemImage: "square.and.arrow.up")
            }
            .disabled(!canExportSelectedModSet)
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

            if let exportable = ModManagerViewModel.shared.exportableSelectedModSet() {
                ShareLink(item: exportable, preview: SharePreview(exportable.name)) {
                    Label(AppStrings.Commands.shareModSet, systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            commandButton(.deleteModSet)
        }
    }

    private var canExportSelectedModSet: Bool {
        ModManagerViewModel.shared.state.modSetSelection.selectedSet != nil
    }

    private func importModSetFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SeedBoxSetDocument.contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            let didAccess = url.startAccessingSecurityScopedResource()
            await ModManagerViewModel.shared.importModSet(fromFileAt: url)
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func exportSelectedModSetToPanel() {
        let viewModel = ModManagerViewModel.shared
        guard
            let selectedSet = viewModel.state.modSetSelection.selectedSet,
            let data = viewModel.exportDataForSelectedModSet()
        else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [SeedBoxSetDocument.contentType]
        panel.nameFieldStringValue = "\(selectedSet.name).\(SeedBoxSetDocument.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        try? data.write(to: url, options: .atomic)
        if didAccess {
            url.stopAccessingSecurityScopedResource()
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
