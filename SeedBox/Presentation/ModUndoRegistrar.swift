import Foundation

/// Registers undoable mod operations with a native `UndoManager`.
///
/// Undo and redo are wired through the system `UndoManager` (so the Edit menu
/// items and ⌘Z / ⇧⌘Z work automatically) rather than a parallel history.
/// Because the underlying mod operations are async and file-backed, each undo
/// re-registers its redo synchronously — while the manager is still undoing, so
/// it lands on the redo stack — and only performs the inverse when the mod is
/// still in the state the original action left it in. That guard keeps undo
/// from silently clobbering a newer change the user made in between.
@MainActor
enum ModUndoRegistrar {
    static func registerModToggle(
        in undoManager: UndoManager,
        viewModel: ModManagerViewModel,
        modID: String,
        restoringTo previousEnabled: Bool,
        appliedValue: Bool
    ) {
        undoManager.registerUndo(withTarget: viewModel) { viewModel in
            MainActor.assumeIsolated {
                guard
                    let current = viewModel.state.mods.first(where: { $0.id == modID }),
                    current.isEnabled == appliedValue
                else {
                    // The mod changed since the action; skip rather than
                    // overwrite the newer state. No redo is registered.
                    return
                }

                // Register the redo now, while still undoing, so it is filed on
                // the redo stack with the values swapped.
                registerModToggle(
                    in: undoManager,
                    viewModel: viewModel,
                    modID: modID,
                    restoringTo: appliedValue,
                    appliedValue: previousEnabled
                )

                Task { await viewModel.setMod(current, enabled: previousEnabled) }
            }
        }

        undoManager.setActionName(
            appliedValue ? AppStrings.Undo.enableMod : AppStrings.Undo.disableMod
        )
    }

    /// Registers undo for applying a Mod Set. Undo re-applies the previously
    /// selected set, and only when the set this action applied is still the
    /// selected one, so a later selection is not silently reverted.
    static func registerModSetApply(
        in undoManager: UndoManager,
        viewModel: ModManagerViewModel,
        previousSetID: String,
        appliedSetID: String
    ) {
        undoManager.registerUndo(withTarget: viewModel) { viewModel in
            MainActor.assumeIsolated {
                guard viewModel.state.selectedModSetID == appliedSetID else {
                    return
                }

                registerModSetApply(
                    in: undoManager,
                    viewModel: viewModel,
                    previousSetID: appliedSetID,
                    appliedSetID: previousSetID
                )

                Task { await viewModel.selectModSet(id: previousSetID) }
            }
        }

        undoManager.setActionName(AppStrings.Undo.applyModSet)
    }

    /// Registers undo for renaming a Mod Set. Undo renames it back, but only
    /// while that set is still the selected one and still carries the new name,
    /// so a later rename or selection change is not clobbered.
    static func registerModSetRename(
        in undoManager: UndoManager,
        viewModel: ModManagerViewModel,
        setID: String,
        previousName: String,
        newName: String
    ) {
        undoManager.registerUndo(withTarget: viewModel) { viewModel in
            MainActor.assumeIsolated {
                guard
                    let selected = viewModel.state.modSetSelection.selectedSet,
                    selected.id == setID,
                    selected.name == newName
                else {
                    return
                }

                registerModSetRename(
                    in: undoManager,
                    viewModel: viewModel,
                    setID: setID,
                    previousName: newName,
                    newName: previousName
                )

                Task { await viewModel.renameSelectedModSet(to: previousName) }
            }
        }

        undoManager.setActionName(AppStrings.Undo.renameModSet)
    }
}
