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

                // Detached so the inverse does not inherit the caller's
                // task-local context (e.g. an async test's), whose teardown can
                // race the spawned task. The call still hops to the main actor.
                Task.detached { await viewModel.setMod(current, enabled: previousEnabled) }
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

                Task.detached { await viewModel.selectModSet(id: previousSetID) }
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

                Task.detached { await viewModel.renameSelectedModSet(to: previousName) }
            }
        }

        undoManager.setActionName(AppStrings.Undo.renameModSet)
    }

    /// Whether a just-deleted mod can still be restored (its deleted archive is
    /// present), used to decide whether to register the undo at all.
    static func canUndoDeletion(of folderName: String, in state: ModManagerState) -> Bool {
        mostRecentDeletedArchive(for: folderName, in: state) != nil
    }

    /// Registers undo for deleting (archiving) a mod. Undo restores the mod's
    /// most recent deleted archive; redo deletes it again. Each direction looks
    /// up the current archive/mod by folder name and skips if it is gone, so a
    /// later manual change is not clobbered.
    static func registerModDeletion(
        in undoManager: UndoManager,
        viewModel: ModManagerViewModel,
        folderName: String
    ) {
        undoManager.registerUndo(withTarget: viewModel) { viewModel in
            MainActor.assumeIsolated {
                guard let archive = mostRecentDeletedArchive(for: folderName, in: viewModel.state) else {
                    return
                }
                registerModRestoration(in: undoManager, viewModel: viewModel, folderName: folderName)
                Task.detached { await viewModel.restoreArchivedMods([archive]) }
            }
        }
        undoManager.setActionName(AppStrings.Undo.deleteMod)
    }

    private static func registerModRestoration(
        in undoManager: UndoManager,
        viewModel: ModManagerViewModel,
        folderName: String
    ) {
        undoManager.registerUndo(withTarget: viewModel) { viewModel in
            MainActor.assumeIsolated {
                let token = folderName.normalizedFolderToken
                guard let mod = viewModel.state.mods.first(where: {
                    $0.enabledFolderName.normalizedFolderToken == token
                }) else {
                    return
                }
                registerModDeletion(in: undoManager, viewModel: viewModel, folderName: folderName)
                Task.detached { await viewModel.deleteMod(mod) }
            }
        }
        undoManager.setActionName(AppStrings.Undo.deleteMod)
    }

    private static func mostRecentDeletedArchive(
        for folderName: String,
        in state: ModManagerState
    ) -> ArchivedModInfo? {
        let token = folderName.normalizedFolderToken
        return state.archivedMods
            .filter { $0.reason == .deleted && $0.enabledFolderName.normalizedFolderToken == token }
            .max { ($0.archivedDate ?? .distantPast) < ($1.archivedDate ?? .distantPast) }
    }

    /// Registers undo for an action that created or removed a Mod Set.
    ///
    /// `deleted` describes the state the action produced: `true` when the set
    /// was deleted (undo restores it), `false` when it was created/duplicated
    /// (undo deletes it). The undo runs only when the set's presence still
    /// matches what the action produced, so a later change is not clobbered.
    static func registerModSetExistence(
        in undoManager: UndoManager,
        viewModel: ModManagerViewModel,
        set: ModSet,
        deleted: Bool,
        actionName: String
    ) {
        undoManager.registerUndo(withTarget: viewModel) { viewModel in
            MainActor.assumeIsolated {
                let exists = viewModel.state.modSets.contains { $0.id == set.id }
                guard exists == !deleted else {
                    return
                }

                registerModSetExistence(
                    in: undoManager,
                    viewModel: viewModel,
                    set: set,
                    deleted: !deleted,
                    actionName: actionName
                )

                if deleted {
                    Task.detached { await viewModel.restoreModSet(set) }
                } else {
                    Task.detached { await viewModel.deleteModSet(set) }
                }
            }
        }

        undoManager.setActionName(actionName)
    }
}
