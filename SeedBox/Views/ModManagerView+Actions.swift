import Foundation
import SwiftUI

extension ModManagerView {
    @ToolbarContentBuilder
    func toolbarContent(_ presentationState: ModManagerPresentationState) -> some ToolbarContent {
        ModManagerToolbar(
            presentationState: presentationState,
            isShowingModInspector: presentation.isShowingModInspector,
            actions: actions
        )
    }

    func commandContext(_ presentationState: ModManagerPresentationState) -> ModManagerCommandContext {
        ModManagerCommandContext(
            presentationState: presentationState,
            isShowingModInspector: presentation.isShowingModInspector,
            actions: actions
        )
    }

    var actions: ModManagerActions {
        ModManagerActions(
            chooseModsFolder: chooseModsFolder,
            addMods: addMods,
            refresh: {
                Task {
                    await viewModel.refresh()
                }
            },
            showProblems: {
                openRoute(.problems)
            },
            showActivity: {
                openRoute(.activity)
            },
            showRestoreHistory: {
                openRoute(.restoreHistory)
            },
            showModInspector: showModInspector,
            createModSet: createModSet,
            duplicateSelectedModSet: duplicateSelectedModSet,
            renameSelectedModSet: renameSelectedModSet,
            deleteSelectedModSet: requestDeleteSelectedModSet,
            compareSelectedModSet: compareSelectedModSet,
            revealModsFolder: viewModel.revealModsFolder,
            revealArchivedModsFolder: viewModel.revealArchivedModsFolder,
            pruneExpiredArchives: pruneExpiredArchives,
            restorePreviousVersion: restorePreviousVersion,
            revealSelectedMod: revealSelectedMod,
            deleteSelectedMod: requestDeleteSelectedMod
        )
    }

    func chooseModsFolder() {
        presentation.isChoosingModsFolder = true
    }

    @discardableResult
    func openRoute(_ route: SeedBoxRoute) -> SeedBoxRouteDispatchResult {
        SeedBoxRouteDispatcher(state: presentationState.state).dispatch(
            route,
            presentation: &presentation,
            selectedLibraryItemID: &selectedLibraryItemID,
            selectedModIDs: &selectedModIDs
        )
    }

    func addMods() {
        presentation.isAddingMods = true
    }

    func createModFolder() {
        Task {
            await viewModel.createModFolder()
        }
    }

    func showModInspector() {
        guard presentationState.selection.hasSelectedMod else {
            return
        }

        presentation.isShowingModInspector.toggle()
    }

    func restorePreviousVersion() {
        guard presentationState.canEditDisplayedModStates,
              let selectedMod = presentationState.selection.mod
        else {
            return
        }

        Task {
            await viewModel.restorePreviousVersion(of: selectedMod)
        }
    }

    func restoreArchivedMods(_ archivedMods: [ArchivedModInfo]) {
        guard !archivedMods.isEmpty else {
            return
        }

        presentation.dismissSheet()
        Task {
            await viewModel.restoreArchivedMods(archivedMods)
        }
    }

    func deleteArchivedMods(_ archivedMods: [ArchivedModInfo]) {
        guard !archivedMods.isEmpty else {
            return
        }

        presentation.dismissSheet()
        Task {
            await viewModel.deleteArchivedMods(archivedMods)
        }
    }

    func pruneExpiredArchives() {
        Task {
            await viewModel.pruneExpiredArchives()
        }
    }

    func resolveDuplicateGroup(_ id: String) {
        Task {
            await viewModel.resolveDuplicateGroup(id: id)
        }
    }

    func requestSelectModSet(id: String) {
        guard !presentationState.modSetIsAlreadyApplied(id) else {
            return
        }

        guard let set = presentationState.modSet(withID: id) else {
            selectModSet(id: id)
            return
        }

        if let confirmation = ModDependencyConfirmationFactory.applying(
            set: set,
            in: presentationState.state.modSets,
            dependencyGraph: presentationState.dependencyGraph
        ) {
            presentation.alert = .dependency(confirmation)
            return
        }

        selectModSet(id: id)
    }

    func selectLibraryItem(id: String) {
        let resolvedID = ModLibrarySelection.resolvedID(id, in: presentationState.state)
        let selection = ModLibrarySelection(id: resolvedID)

        switch selection {
        case .builtInSmart, .userSmart:
            selectedLibraryItemID = resolvedID
            selectedModIDs = []
        case .modSet(let id):
            if presentationState.modSetIsAlreadyApplied(id) {
                selectedLibraryItemID = resolvedID
                selectedModIDs = []
                return
            }
            requestSelectModSet(id: id)
        }
    }

    func selectModSet(id: String) {
        let previousSetID = viewModel.state.selectedModSetID
        selectedLibraryItemID = ModLibrarySelection.modSetID(id)
        selectedModIDs = []
        Task {
            await viewModel.selectModSet(id: id)

            // Register undo only when the switch actually applied.
            if previousSetID != id,
               viewModel.state.selectedModSetID == id,
               let undoManager {
                ModUndoRegistrar.registerModSetApply(
                    in: undoManager,
                    viewModel: viewModel,
                    previousSetID: previousSetID,
                    appliedSetID: id
                )
            }
        }
    }

    func syncLibrarySelection(_ presentationState: ModManagerPresentationState) {
        let resolvedID = ModLibrarySelection.resolvedID(
            selectedLibraryItemID,
            in: presentationState.state
        )
        if selectedLibraryItemID != resolvedID {
            selectedLibraryItemID = resolvedID
        }
    }

    func syncLaunchModUpdateCheck(_ presentationState: ModManagerPresentationState) {
        guard !presentation.hasHandledLaunchModUpdateCheck,
              presentationState.state.hasLoadedMods,
              presentationState.canManageMods
        else {
            return
        }

        presentation.hasHandledLaunchModUpdateCheck = true
        if presentationState.state.checksForModUpdates {
            Task {
                await viewModel.checkForModUpdates()
            }
        } else {
            guard presentation.alert == nil else {
                presentation.hasHandledLaunchModUpdateCheck = false
                return
            }
            presentation.alert = .modUpdateNetworkAccess
        }
    }

    func previewMods(from urls: [URL]) {
        switch viewModel.prepareImportPreview(from: urls) {
        case .success(let preview):
            presentation.sheet = .importPreview(preview)
        case .failure(let outcome):
            presentImportPreviewFailure(outcome)
        }
    }

    func presentImportPreviewFailure(_ outcome: WorkspaceActionOutcome) {
        switch outcome {
        case .completed:
            break
        case .recorded(let event):
            presentation.alert = .message(
                MessageAlert(
                    title: AppStrings.Alerts.couldNotPreviewModsTitle,
                    message: event.message
                )
            )
        case .folderAccessLost(let message):
            guard let message else {
                return
            }
            presentation.alert = .message(
                MessageAlert(
                    title: AppStrings.Alerts.couldNotPreviewModsTitle,
                    message: message
                )
            )
        }
    }

    func installPreviewedMods(_ preview: ModImportPreview) {
        presentation.dismissSheet()
        Task {
            await viewModel.addPreviewedMods(preview)
        }
    }

    func installDroppedMods(from urls: [URL]) -> Bool {
        guard presentationState.canManageMods else {
            return false
        }

        let installableURLs = urls.filter(Self.canDropAsModSource)
        guard !installableURLs.isEmpty else {
            return false
        }

        previewMods(from: installableURLs)
        return true
    }

    static func canDropAsModSource(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
            || url.hasDirectoryPath
            || FileManager.default.directoryExists(at: url)
    }

    func createModSet() {
        presentation.sheet = .modSetEditor(.create)
    }

    func duplicateSelectedModSet() {
        guard let selectedSet = presentationState.selectedSet else {
            return
        }

        presentation.sheet = .modSetEditor(.duplicate(selectedSet))
    }

    func renameSelectedModSet() {
        guard let selectedSet = presentationState.selectedRenamableSet else {
            return
        }

        presentation.sheet = .modSetEditor(.rename(selectedSet))
    }

    func requestDeleteSelectedModSet() {
        if let selectedSet = presentationState.selectedDeletableSet {
            presentation.alert = .deleteModSet(selectedSet)
        }
    }

    func compareSelectedModSet() {
        guard let comparison = presentationState.selectedModSetComparison else {
            return
        }

        presentation.sheet = .modSetComparison(comparison)
    }

    func revealSelectedMod() {
        guard let selectedMod = presentationState.selection.mod else {
            return
        }

        viewModel.revealMod(selectedMod)
    }

    func requestDeleteSelectedMod() {
        if presentationState.canEditDisplayedModStates,
           let selectedMod = presentationState.selection.mod {
            presentation.alert = .deleteMod(selectedMod)
        }
    }

    func syncAppShortcutRequest() {
        guard let request = SeedBoxShortcutRouter.shared.consumePendingRequest() else {
            return
        }

        openRoute(request.route)
    }

    func requestSetModEnabled(_ mod: ModInfo, enabled: Bool) {
        guard presentationState.canEditDisplayedModStates,
              mod.isEnabled != enabled
        else {
            return
        }

        if enabled {
            if let confirmation = ModDependencyConfirmationFactory.enabling(
                mod: mod,
                dependencyGraph: presentationState.dependencyGraph
            ) {
                presentation.alert = .dependency(confirmation)
                return
            }
        } else {
            if let confirmation = ModDependencyConfirmationFactory.disabling(
                mod: mod,
                dependencyGraph: presentationState.dependencyGraph
            ) {
                presentation.alert = .dependency(confirmation)
                return
            }
        }

        setMod(mod, enabled: enabled)
    }

    func setMod(_ mod: ModInfo, enabled: Bool) {
        let previousEnabled = mod.isEnabled
        Task {
            await viewModel.setMod(mod, enabled: enabled)

            // Register undo only for an actual change, after it is applied.
            if previousEnabled != enabled, let undoManager {
                ModUndoRegistrar.registerModToggle(
                    in: undoManager,
                    viewModel: viewModel,
                    modID: mod.id,
                    restoringTo: previousEnabled,
                    appliedValue: enabled
                )
            }
        }
    }

    /// Reverts the selected mod's local override back to the base set's state.
    /// Setting the mod to the inherited value lets the set's delta recompute
    /// drop the override automatically.
    func revertSelectedModToBase() {
        guard
            let mod = presentationState.selection.mod,
            let context = presentationState.selectedSetInheritanceContext,
            context.state(for: mod) == .overridden
        else {
            return
        }

        setMod(mod, enabled: context.baseEnabled(for: mod))
    }

    func setMods(_ mods: [ModInfo], enabled: Bool) {
        Task {
            await viewModel.setMods(mods, enabled: enabled)
        }
    }

    func performDependencyAction(_ action: DependencyConfirmationAction) {
        presentation.dismissAlert()

        switch action {
        case .setMod(let mod, let enabled):
            setMod(mod, enabled: enabled)
        case .setMods(let mods, let enabled):
            setMods(mods, enabled: enabled)
        case .selectModSet(let id):
            selectModSet(id: id)
        }
    }

    func commitModSetEditor(mode: ModSetEditorMode, name: String, parentID: String?) async {
        switch mode {
        case .create:
            await viewModel.createModSet(named: name, parentID: parentID)
        case .duplicate:
            await viewModel.duplicateSelectedModSet(named: name, parentID: parentID)
        case .rename:
            await viewModel.renameSelectedModSet(to: name)
        }
        presentation.dismissSheet()
    }

    func removeSelectedModID(_ id: String) {
        selectedModIDs.remove(id)
    }

    func syncLastSessionNotice() {
        guard let notice = viewModel.state.pendingLastSessionNotice,
              presentation.alert == nil
        else {
            return
        }

        presentation.alert = .lastSessionNotice(notice)
    }

    func syncSourceCleanupOffer() {
        presentation.resetSourceCleanupChoice()
        if let offer = presentationState.pendingSourceCleanupOffer {
            presentation.sheet = .sourceCleanup(offer)
        } else if case .sourceCleanup = presentation.sheet {
            presentation.dismissSheet()
        }
    }

    func syncBisectionSheet() {
        if presentationState.state.bisectionSession != nil {
            if presentation.sheet?.id != ModManagerSheet.bisection.id {
                presentation.sheet = .bisection
            }
        } else if case .bisection = presentation.sheet {
            presentation.dismissSheet()
        }
    }

    func startBisection() {
        Task {
            await viewModel.startBisection()
        }
    }
}
