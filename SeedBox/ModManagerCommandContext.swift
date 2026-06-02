import SwiftUI

struct ModManagerCommandContext {
    var state: ModManagerState
    var selectedMod: ModInfo?
    var chooseModsFolder: () -> Void
    var addMods: () -> Void
    var refresh: () -> Void
    var createModSet: () -> Void
    var duplicateSelectedModSet: () -> Void
    var renameSelectedModSet: () -> Void
    var deleteSelectedModSet: () -> Void
    var revealModsFolder: () -> Void
    var revealSelectedMod: () -> Void
    var deleteSelectedMod: () -> Void

    var canManageMods: Bool {
        state.readiness.canManageMods
    }

    var modSetSelection: ModSetSelectionState {
        state.modSetSelection
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
