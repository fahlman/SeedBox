import SwiftUI

struct ModManagerCommandContext {
    var presentationState: ModManagerPresentationState
    var actions: ModManagerActions

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

    var canShowRestoreHistory: Bool {
        presentationState.canShowRestoreHistory
    }

    var canShowModInspector: Bool {
        presentationState.canShowModInspector
    }

    var canRevealSelectedMod: Bool {
        presentationState.canRevealSelectedMod
    }

    var canDeleteSelectedMod: Bool {
        presentationState.canDeleteSelectedMod
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
