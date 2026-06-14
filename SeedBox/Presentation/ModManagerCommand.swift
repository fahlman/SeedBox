import SwiftUI

enum ModManagerCommand {
    case addMods
    case chooseModsFolder
    case compareModSet
    case createModSet
    case deleteModSet
    case deleteSelectedMod
    case duplicateModSet
    case pruneExpiredArchives
    case refreshModsFolder
    case renameModSet
    case restorePreviousVersion
    case revealArchivedModsFolder
    case revealModsFolder
    case revealSelectedMod
    case showActivity
    case showModInspector
    case showProblems
    case showRestoreHistory

    struct Shortcut {
        var key: KeyEquivalent
        var modifiers: EventModifiers

        init(_ key: KeyEquivalent, modifiers: EventModifiers) {
            self.key = key
            self.modifiers = modifiers
        }
    }

    var systemImage: String {
        switch self {
        case .addMods:
            "square.and.arrow.down"
        case .chooseModsFolder:
            "folder"
        case .compareModSet:
            "rectangle.split.2x1"
        case .createModSet:
            "folder.badge.plus"
        case .deleteModSet:
            "folder.badge.minus"
        case .deleteSelectedMod:
            "trash"
        case .duplicateModSet:
            "doc.on.doc"
        case .pruneExpiredArchives:
            "archivebox"
        case .refreshModsFolder:
            "arrow.clockwise"
        case .renameModSet:
            "pencil"
        case .restorePreviousVersion:
            "arrow.uturn.backward"
        case .revealArchivedModsFolder:
            "archivebox"
        case .revealModsFolder:
            "folder"
        case .revealSelectedMod:
            "eye"
        case .showActivity:
            "clock"
        case .showModInspector:
            "info.circle"
        case .showProblems:
            "exclamationmark.triangle"
        case .showRestoreHistory:
            "clock.arrow.circlepath"
        }
    }

    var shortcut: Shortcut? {
        switch self {
        case .addMods:
            Shortcut("o", modifiers: [.command])
        case .chooseModsFolder:
            Shortcut("o", modifiers: [.command, .option])
        case .compareModSet:
            Shortcut("c", modifiers: [.command, .shift])
        case .createModSet:
            Shortcut("n", modifiers: [.command])
        case .deleteModSet:
            Shortcut(.delete, modifiers: [.command, .shift])
        case .deleteSelectedMod:
            Shortcut(.delete, modifiers: [.command])
        case .duplicateModSet:
            Shortcut("d", modifiers: [.command])
        case .pruneExpiredArchives:
            Shortcut("p", modifiers: [.command, .option])
        case .refreshModsFolder:
            Shortcut("r", modifiers: [.command])
        case .renameModSet:
            Shortcut(.return, modifiers: [])
        case .restorePreviousVersion:
            Shortcut("r", modifiers: [.command, .option])
        case .revealSelectedMod:
            Shortcut("f", modifiers: [.command, .shift])
        case .showActivity:
            Shortcut("l", modifiers: [.command, .option])
        case .showModInspector:
            Shortcut("i", modifiers: [.command])
        case .showProblems:
            Shortcut("0", modifiers: [.command, .shift])
        case .showRestoreHistory:
            Shortcut("r", modifiers: [.command, .shift])
        case .revealArchivedModsFolder, .revealModsFolder:
            nil
        }
    }

    var role: ButtonRole? {
        switch self {
        case .deleteModSet, .deleteSelectedMod:
            .destructive
        default:
            nil
        }
    }

    func title(isShowingModInspector: Bool = false) -> String {
        switch self {
        case .addMods:
            AppStrings.Commands.addMods
        case .chooseModsFolder:
            AppStrings.Commands.chooseModsFolder
        case .compareModSet:
            AppStrings.Commands.compareModSet
        case .createModSet:
            AppStrings.Commands.newModSet
        case .deleteModSet:
            AppStrings.Commands.deleteModSet
        case .deleteSelectedMod:
            AppStrings.Commands.deleteSelectedMod
        case .duplicateModSet:
            AppStrings.Commands.duplicateModSet
        case .pruneExpiredArchives:
            AppStrings.Commands.pruneExpiredArchives
        case .refreshModsFolder:
            AppStrings.Commands.refreshModsFolder
        case .renameModSet:
            AppStrings.Commands.renameModSet
        case .restorePreviousVersion:
            AppStrings.Commands.restorePreviousVersion
        case .revealArchivedModsFolder:
            AppStrings.Commands.revealArchivedModsInFinder
        case .revealModsFolder:
            AppStrings.Commands.revealModsFolderInFinder
        case .revealSelectedMod:
            AppStrings.Commands.revealSelectedModInFinder
        case .showActivity:
            AppStrings.Toolbar.activity
        case .showModInspector:
            if isShowingModInspector {
                AppStrings.Toolbar.hideDetails
            } else {
                AppStrings.Commands.showModDetails
            }
        case .showProblems:
            AppStrings.Toolbar.problems
        case .showRestoreHistory:
            AppStrings.Commands.restoreHistory
        }
    }

    func isEnabled(in state: ModManagerPresentationState) -> Bool {
        switch self {
        case .addMods, .createModSet, .refreshModsFolder:
            state.canManageMods
        case .chooseModsFolder:
            true
        case .compareModSet:
            state.canCompareSelectedModSet
        case .deleteModSet:
            state.canManageMods && state.selectedDeletableSet != nil
        case .deleteSelectedMod:
            state.canDeleteSelectedMod
        case .duplicateModSet:
            state.canManageMods && state.selectedSet != nil
        case .pruneExpiredArchives:
            state.canPruneExpiredArchives
        case .renameModSet:
            state.canManageMods && state.selectedRenamableSet != nil
        case .restorePreviousVersion:
            state.canRestorePreviousVersion
        case .revealArchivedModsFolder:
            true
        case .revealModsFolder:
            state.canManageMods
        case .revealSelectedMod:
            state.canRevealSelectedMod
        case .showActivity:
            state.canShowActivity
        case .showModInspector:
            state.canShowModInspector
        case .showProblems:
            state.canShowProblems
        case .showRestoreHistory:
            state.canShowRestoreHistory
        }
    }

    func isEnabled(in context: ModManagerCommandContext?) -> Bool {
        guard let context else {
            return false
        }

        return isEnabled(in: context.presentationState)
    }

    func perform(with actions: ModManagerActions) {
        switch self {
        case .addMods:
            actions.addMods()
        case .chooseModsFolder:
            actions.chooseModsFolder()
        case .compareModSet:
            actions.compareSelectedModSet()
        case .createModSet:
            actions.createModSet()
        case .deleteModSet:
            actions.deleteSelectedModSet()
        case .deleteSelectedMod:
            actions.deleteSelectedMod()
        case .duplicateModSet:
            actions.duplicateSelectedModSet()
        case .pruneExpiredArchives:
            actions.pruneExpiredArchives()
        case .refreshModsFolder:
            actions.refresh()
        case .renameModSet:
            actions.renameSelectedModSet()
        case .restorePreviousVersion:
            actions.restorePreviousVersion()
        case .revealArchivedModsFolder:
            actions.revealArchivedModsFolder()
        case .revealModsFolder:
            actions.revealModsFolder()
        case .revealSelectedMod:
            actions.revealSelectedMod()
        case .showActivity:
            actions.showActivity()
        case .showModInspector:
            actions.showModInspector()
        case .showProblems:
            actions.showProblems()
        case .showRestoreHistory:
            actions.showRestoreHistory()
        }
    }

    @ViewBuilder
    func label(isShowingModInspector: Bool = false) -> some View {
        Label(
            title(isShowingModInspector: isShowingModInspector),
            systemImage: systemImage
        )
    }
}

extension View {
    @ViewBuilder
    func modManagerKeyboardShortcut(_ shortcut: ModManagerCommand.Shortcut?) -> some View {
        if let shortcut {
            keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            self
        }
    }
}
