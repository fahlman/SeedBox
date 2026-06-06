import Foundation
import SwiftUI

extension ModManagerView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ModManagerToolbar(
            presentationState: presentationState,
            isShowingModInspector: presentation.isShowingModInspector,
            selectModSet: requestSelectModSet,
            actions: actions
        )
    }

    var commandContext: ModManagerCommandContext {
        ModManagerCommandContext(
            presentationState: presentationState,
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
                presentation.sheet = .problems
            },
            showActivity: {
                presentation.sheet = .activity
            },
            showRestoreHistory: {
                presentation.sheet = .restoreHistory
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
        guard let selectedMod = presentationState.selection.mod else {
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

    func pruneExpiredArchives() {
        Task {
            await viewModel.pruneExpiredArchives()
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
            dependencyGraph: presentationState.dependencyGraph
        ) {
            presentation.alert = .dependency(confirmation)
            return
        }

        selectModSet(id: id)
    }

    func selectModSet(id: String) {
        Task {
            await viewModel.selectModSet(id: id)
        }
    }

    func previewMods(from urls: [URL]) {
        guard let preview = viewModel.prepareImportPreview(from: urls) else {
            return
        }

        presentation.sheet = .importPreview(preview)
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
        if let selectedMod = presentationState.selection.mod {
            presentation.alert = .deleteMod(selectedMod)
        }
    }

    func requestSetModEnabled(_ mod: ModInfo, enabled: Bool) {
        guard mod.isEnabled != enabled else {
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
        Task {
            await viewModel.setMod(mod, enabled: enabled)
        }
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

    func commitModSetEditor(mode: ModSetEditorMode, name: String) async {
        switch mode {
        case .create:
            await viewModel.createModSet(named: name)
        case .duplicate:
            await viewModel.duplicateSelectedModSet(named: name)
        case .rename:
            await viewModel.renameSelectedModSet(to: name)
        }
        presentation.dismissSheet()
    }

    func removeSelectedModID(_ id: String) {
        selectedModIDs.remove(id)
    }

    func syncSourceCleanupOffer() {
        presentation.resetSourceCleanupChoice()
        if let offer = presentationState.pendingSourceCleanupOffer {
            presentation.sheet = .sourceCleanup(offer)
        } else if case .sourceCleanup = presentation.sheet {
            presentation.dismissSheet()
        }
    }
}
