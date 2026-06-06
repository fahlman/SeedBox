import SwiftUI

struct ModManagerCommandContext {
    var presentationState: ModManagerPresentationState
    var chooseModsFolder: () -> Void
    var addMods: () -> Void
    var refresh: () -> Void
    var showProblems: () -> Void
    var showActivity: () -> Void
    var showModInspector: () -> Void
    var createModSet: () -> Void
    var duplicateSelectedModSet: () -> Void
    var renameSelectedModSet: () -> Void
    var deleteSelectedModSet: () -> Void
    var compareSelectedModSet: () -> Void
    var revealModsFolder: () -> Void
    var revealArchivedModsFolder: () -> Void
    var pruneExpiredArchives: () -> Void
    var restorePreviousVersion: () -> Void
    var revealSelectedMod: () -> Void
    var deleteSelectedMod: () -> Void

    var selectedMod: ModInfo? {
        presentationState.selection.mod
    }

    var canManageMods: Bool {
        presentationState.canManageMods
    }

    var modSetSelection: ModSetSelectionState {
        presentationState.modSetSelection
    }

    var canRestorePreviousVersion: Bool {
        presentationState.canRestorePreviousVersion
    }

    var canCompareSelectedModSet: Bool {
        presentationState.canCompareSelectedModSet
    }

    var canPruneExpiredArchives: Bool {
        presentationState.canPruneExpiredArchives
    }

    var canShowProblems: Bool {
        presentationState.canShowProblems
    }

    var canShowActivity: Bool {
        presentationState.canShowActivity
    }
}

private struct ModManagerCommandContextKey: FocusedValueKey {
    typealias Value = ModManagerCommandContext
}

extension FocusedValues {
    var modManagerCommandContext: ModManagerCommandContext? {
        get { self[ModManagerCommandContextKey.self] }
        set { self[ModManagerCommandContextKey.self] = newValue }
    }
}
