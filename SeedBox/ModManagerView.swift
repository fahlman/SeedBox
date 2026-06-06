import SwiftUI
import UniformTypeIdentifiers

struct ModManagerView: View {
    @ObservedObject var viewModel: ModManagerViewModel
    @Binding var searchText: String
    @Binding var selectedModIDs: Set<String>
    @State private var modSetEditorMode: ModSetEditorMode?
    @State private var modPendingDeletion: ModInfo?
    @State private var modSetPendingDeletion: ModSet?
    @State private var dependencyConfirmation: DependencyConfirmation?
    @State private var importPreview: ModImportPreview?
    @State private var modSetComparison: ModSetComparison?
    @State private var isShowingProblems = false
    @State private var isShowingActivity = false
    @State private var isShowingModInspector = false
    @State private var isAddingMods = false
    @State private var isChoosingModsFolder = false
    @State private var modDropIsTargeted = false
    @State private var remembersSourceCleanupChoice = false

    private static var addableModContentTypes: [UTType] {
        var contentTypes: [UTType] = [.folder]
        if let zipType = UTType(filenameExtension: "zip") {
            contentTypes.append(zipType)
        }
        return contentTypes
    }

    private var presentationState: ModManagerPresentationState {
        ModManagerPresentationState(
            state: viewModel.state,
            searchText: searchText,
            selectedModIDs: selectedModIDs
        )
    }

    var body: some View {
        content
            .background(.background)
            .overlay {
                dropOverlay
            }
            .dropDestination(for: URL.self) { urls, _ in
                installDroppedMods(from: urls)
            } isTargeted: { isTargeted in
                modDropIsTargeted = isTargeted
            }
            .toolbar {
                toolbarContent
            }
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: AppStrings.Search.prompt
            )
            .fileImporter(
                isPresented: $isAddingMods,
                allowedContentTypes: Self.addableModContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    previewMods(from: urls)
                case .failure(let error):
                    viewModel.recordAddModsSelectionError(error)
                }
            }
            .fileImporter(
                isPresented: $isChoosingModsFolder,
                allowedContentTypes: [.folder]
            ) { result in
                switch result {
                case .success(let url):
                    Task {
                        await viewModel.chooseModsFolder(url)
                    }
                case .failure(let error):
                    viewModel.recordModsFolderSelectionError(error)
                }
            }
            .sheet(item: $modSetEditorMode) { mode in
                ModSetNameSheet(
                    mode: mode,
                    onCancel: {
                        modSetEditorMode = nil
                    },
                    onCommit: { name in
                        Task {
                            await commitModSetEditor(mode: mode, name: name)
                        }
                    }
                )
            }
            .sheet(item: $importPreview) { preview in
                ModImportPreviewSheet(
                    preview: preview,
                    cancel: {
                        ModLibrary.discardImportPreview(preview)
                        importPreview = nil
                    },
                    install: {
                        installPreviewedMods(preview)
                    }
                )
            }
            .sheet(isPresented: $isShowingProblems) {
                ProblemsSheet(
                    dependencyIssues: presentationState.state.dependencyIssues,
                    invalidFolders: presentationState.state.invalidModFolders,
                    duplicateGroups: presentationState.state.duplicateGroups,
                    close: {
                        isShowingProblems = false
                    }
                )
            }
            .sheet(isPresented: $isShowingActivity) {
                ActivitySheet(
                    auditTrail: viewModel.state.auditTrail,
                    close: {
                        isShowingActivity = false
                    }
                )
            }
            .sheet(item: $modSetComparison) { comparison in
                ModSetComparisonSheet(comparison: comparison) {
                    modSetComparison = nil
                }
            }
            .alert(
                "Delete Mod?",
                isPresented: modDeletionAlertIsPresented,
                presenting: modPendingDeletion
            ) { mod in
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteMod(mod)
                        removeSelectedModID(mod.id)
                        modPendingDeletion = nil
                    }
                }

                Button("Cancel", role: .cancel) {
                    modPendingDeletion = nil
                }
            } message: { mod in
                Text(AppStrings.Alerts.deleteModMessage(
                    mod.displayName,
                    retentionDays: viewModel.state.archiveSettings.normalizedRetentionDays
                ))
            }
            .alert(
                "Delete Mod Set?",
                isPresented: modSetDeletionAlertIsPresented,
                presenting: modSetPendingDeletion
            ) { set in
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteModSet(set)
                        modSetPendingDeletion = nil
                    }
                }

                Button("Cancel", role: .cancel) {
                    modSetPendingDeletion = nil
                }
            } message: { set in
                Text(AppStrings.Alerts.deleteModSetMessage(set.name))
            }
            .alert(
                dependencyConfirmation?.title ?? AppStrings.Alerts.dependencyWarning,
                isPresented: dependencyConfirmationAlertIsPresented,
                presenting: dependencyConfirmation
            ) { confirmation in
                Button("Cancel", role: .cancel) {
                    dependencyConfirmation = nil
                }

                if let repairTitle = confirmation.repairTitle,
                   let repairAction = confirmation.repairAction {
                    Button(repairTitle, role: confirmation.repairRole) {
                        performDependencyAction(repairAction)
                    }
                }

                Button(confirmation.confirmTitle, role: confirmation.confirmRole) {
                    performDependencyAction(confirmation.action)
                }
            } message: { confirmation in
                Text(confirmation.message)
            }
            .sheet(item: sourceCleanupSheetItem) { offer in
                SourceCleanupOfferSheet(
                    offer: offer,
                    remembersChoice: $remembersSourceCleanupChoice,
                    keepFiles: {
                        viewModel.keepSourceFiles(
                            for: offer,
                            remembersChoice: remembersSourceCleanupChoice
                        )
                    },
                    moveToTrash: {
                        Task {
                            await viewModel.moveSourceFilesToTrash(
                                for: offer,
                                remembersChoice: remembersSourceCleanupChoice
                            )
                        }
                    },
                    dismissNotice: {
                        viewModel.dismissSourceCleanupOffer()
                    }
                )
            }
            .onChange(of: viewModel.state.pendingSourceCleanupOffer?.id) {
                remembersSourceCleanupChoice = false
            }
            .focusedValue(\.modManagerCommandContext, commandContext)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if presentationState.canManageMods {
                managedContent
            } else {
                SetupEmptyState(
                    viewModel: viewModel,
                    chooseModsFolder: chooseModsFolder
                )
            }

            if !viewModel.state.statusLineMessage.isEmpty {
                Divider()
                Text(viewModel.state.statusLineMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
        }
    }

    private var managedContent: some View {
        HStack(spacing: 0) {
            ModList(
                mods: presentationState.filteredMods,
                viewModel: viewModel,
                selectedModIDs: $selectedModIDs,
                selectedMod: presentationState.selection.mod,
                addMods: addMods,
                requestSetModEnabled: requestSetModEnabled,
                revealSelectedMod: revealSelectedMod,
                requestDeleteSelectedMod: requestDeleteSelectedMod
            )

            if isShowingModInspector, let selectedMod = presentationState.selection.mod {
                Divider()
                ModDetailInspector(
                    mod: selectedMod,
                    dependencyStatuses: presentationState.selection.dependencyStatuses,
                    dependents: presentationState.selection.dependents,
                    previousArchivedVersion: presentationState.selection.previousArchivedVersion,
                    archivedVersions: presentationState.selection.archivedVersions,
                    duplicateGroups: presentationState.selection.duplicateGroups,
                    archiveSummary: viewModel.state.archiveSummary,
                    restorePreviousVersion: restorePreviousVersion,
                    revealSelectedMod: revealSelectedMod,
                    pruneExpiredArchives: pruneExpiredArchives
                )
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
            }
        }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if modDropIsTargeted && presentationState.canManageMods {
            Rectangle()
                .fill(Color.accentColor.opacity(0.08))
                .overlay {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
                .allowsHitTesting(false)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ModManagerToolbar(
            presentationState: presentationState,
            isShowingModInspector: isShowingModInspector,
            selectModSet: requestSelectModSet,
            showProblems: {
                isShowingProblems = true
            },
            showActivity: {
                isShowingActivity = true
            },
            showModInspector: showModInspector,
            createModSet: createModSet,
            duplicateSelectedModSet: duplicateSelectedModSet,
            renameSelectedModSet: renameSelectedModSet,
            deleteSelectedModSet: requestDeleteSelectedModSet,
            compareSelectedModSet: compareSelectedModSet,
            addMods: addMods,
            pruneExpiredArchives: pruneExpiredArchives,
            restorePreviousVersion: restorePreviousVersion,
            revealSelectedMod: revealSelectedMod,
            deleteSelectedMod: requestDeleteSelectedMod
        )
    }

    private var commandContext: ModManagerCommandContext {
        ModManagerCommandContext(
            presentationState: presentationState,
            chooseModsFolder: chooseModsFolder,
            addMods: addMods,
            refresh: {
                Task {
                    await viewModel.refresh()
                }
            },
            showProblems: {
                isShowingProblems = true
            },
            showActivity: {
                isShowingActivity = true
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

    private func chooseModsFolder() {
        isChoosingModsFolder = true
    }

    private func addMods() {
        isAddingMods = true
    }

    private func showModInspector() {
        guard presentationState.selection.hasSelectedMod else {
            return
        }

        isShowingModInspector.toggle()
    }

    private func restorePreviousVersion() {
        guard let selectedMod = presentationState.selection.mod else {
            return
        }

        Task {
            await viewModel.restorePreviousVersion(of: selectedMod)
        }
    }

    private func pruneExpiredArchives() {
        Task {
            await viewModel.pruneExpiredArchives()
        }
    }

    private func requestSelectModSet(id: String) {
        guard id != presentationState.state.selectedModSetID
                || presentationState.state.appliedModSetID != id
        else {
            return
        }

        guard let set = presentationState.state.modSets.first(where: { $0.id == id }) else {
            selectModSet(id: id)
            return
        }

        let issues = presentationState.dependencyGraph.issues(applying: set)
        guard !issues.isEmpty else {
            selectModSet(id: id)
            return
        }

        dependencyConfirmation = DependencyConfirmation(
            title: AppStrings.Alerts.unresolvedRequiredDependencies,
            message: modSetDependencyWarningMessage(set: set, issues: issues),
            confirmTitle: AppStrings.Alerts.applyAnyway,
            confirmRole: nil,
            action: .selectModSet(id)
        )
    }

    private func selectModSet(id: String) {
        Task {
            await viewModel.selectModSet(id: id)
        }
    }

    private func previewMods(from urls: [URL]) {
        guard let preview = viewModel.prepareImportPreview(from: urls) else {
            return
        }

        importPreview = preview
    }

    private func installPreviewedMods(_ preview: ModImportPreview) {
        importPreview = nil
        Task {
            await viewModel.addPreviewedMods(preview)
        }
    }

    private func installDroppedMods(from urls: [URL]) -> Bool {
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

    private static func canDropAsModSource(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
            || url.hasDirectoryPath
            || FileManager.default.directoryExists(at: url)
    }

    private func createModSet() {
        modSetEditorMode = .create
    }

    private func duplicateSelectedModSet() {
        guard let selectedSet = presentationState.state.modSetSelection.selectedSet else {
            return
        }

        modSetEditorMode = .duplicate(selectedSet)
    }

    private func renameSelectedModSet() {
        guard let selectedSet = presentationState.state.modSetSelection.selectedRenamableSet else {
            return
        }

        modSetEditorMode = .rename(selectedSet)
    }

    private func requestDeleteSelectedModSet() {
        modSetPendingDeletion = presentationState.state.modSetSelection.selectedDeletableSet
    }

    private func compareSelectedModSet() {
        guard let comparison = presentationState.selectedModSetComparison else {
            return
        }

        modSetComparison = comparison
    }

    private func revealSelectedMod() {
        guard let selectedMod = presentationState.selection.mod else {
            return
        }

        viewModel.revealMod(selectedMod)
    }

    private func requestDeleteSelectedMod() {
        modPendingDeletion = presentationState.selection.mod
    }

    private func requestSetModEnabled(_ mod: ModInfo, enabled: Bool) {
        guard mod.isEnabled != enabled else {
            return
        }

        if enabled {
            let issues = presentationState.dependencyGraph.requiredIssuesIfEnabled(mod)
            guard issues.isEmpty else {
                let repairMods = presentationState.dependencyGraph.disabledModsSatisfying(issues)
                let canRepairAllIssues = repairMods.count == issues.count
                dependencyConfirmation = DependencyConfirmation(
                    title: AppStrings.Alerts.missingRequiredDependencies,
                    message: enableDependencyWarningMessage(mod: mod, issues: issues),
                    confirmTitle: AppStrings.Alerts.enableAnyway,
                    confirmRole: nil,
                    action: .setMod(mod, enabled: true),
                    repairTitle: canRepairAllIssues ? AppStrings.Alerts.enableRequiredDependencies : nil,
                    repairRole: nil,
                    repairAction: canRepairAllIssues ? .setMods(repairMods + [mod], enabled: true) : nil
                )
                return
            }
        } else {
            let dependents = presentationState.dependencyGraph.enabledDependentsIfDisabled(mod)
            guard dependents.isEmpty else {
                dependencyConfirmation = DependencyConfirmation(
                    title: AppStrings.Alerts.requiredByEnabledMods,
                    message: disableDependencyWarningMessage(mod: mod, dependents: dependents),
                    confirmTitle: AppStrings.Alerts.disableAnyway,
                    confirmRole: .destructive,
                    action: .setMod(mod, enabled: false),
                    repairTitle: AppStrings.Alerts.disableDependentMods,
                    repairRole: .destructive,
                    repairAction: .setMods(dependents + [mod], enabled: false)
                )
                return
            }
        }

        setMod(mod, enabled: enabled)
    }

    private func setMod(_ mod: ModInfo, enabled: Bool) {
        Task {
            await viewModel.setMod(mod, enabled: enabled)
        }
    }

    private func setMods(_ mods: [ModInfo], enabled: Bool) {
        Task {
            await viewModel.setMods(mods, enabled: enabled)
        }
    }

    private func performDependencyAction(_ action: DependencyConfirmationAction) {
        dependencyConfirmation = nil

        switch action {
        case .setMod(let mod, let enabled):
            setMod(mod, enabled: enabled)
        case .setMods(let mods, let enabled):
            setMods(mods, enabled: enabled)
        case .selectModSet(let id):
            selectModSet(id: id)
        }
    }

    private func enableDependencyWarningMessage(
        mod: ModInfo,
        issues: [ModDependencyResolution]
    ) -> String {
        AppStrings.Dependency.enableWarning(
            modName: mod.displayName,
            dependencySummary: AppStrings.Dependency.formattedList(issues.map(\.summaryText)),
            dependencyCount: issues.count
        )
    }

    private func disableDependencyWarningMessage(mod: ModInfo, dependents: [ModInfo]) -> String {
        AppStrings.Dependency.disableWarning(
            modName: mod.displayName,
            dependentSummary: AppStrings.Dependency.formattedList(dependents.map(\.displayName)),
            dependentCount: dependents.count
        )
    }

    private func modSetDependencyWarningMessage(
        set: ModSet,
        issues: [ModDependencyIssue]
    ) -> String {
        if let issue = issues.first, issues.count == 1 {
            return AppStrings.Dependency.singleModSetIssue(
                setName: set.name,
                modName: issue.modName,
                dependencySummary: issue.dependencySummaryText
            )
        }

        let examples = issues
            .prefix(3)
            .map { issue in
                "\(issue.modName): \(issue.dependencySummaryText)"
            }
            .joined(separator: "\n")

        return AppStrings.Dependency.multipleModSetIssues(
            setName: set.name,
            issueCount: issues.count,
            examples: examples
        )
    }

    private func commitModSetEditor(mode: ModSetEditorMode, name: String) async {
        switch mode {
        case .create:
            await viewModel.createModSet(named: name)
        case .duplicate:
            await viewModel.duplicateSelectedModSet(named: name)
        case .rename:
            await viewModel.renameSelectedModSet(to: name)
        }
        modSetEditorMode = nil
    }

    private func removeSelectedModID(_ id: String) {
        selectedModIDs.remove(id)
    }

    private var modDeletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { modPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    modPendingDeletion = nil
                }
            }
        )
    }

    private var modSetDeletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { modSetPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    modSetPendingDeletion = nil
                }
            }
        )
    }

    private var dependencyConfirmationAlertIsPresented: Binding<Bool> {
        Binding(
            get: { dependencyConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    dependencyConfirmation = nil
                }
            }
        )
    }

    private var sourceCleanupSheetItem: Binding<SourceCleanupOffer?> {
        Binding(
            get: { viewModel.state.pendingSourceCleanupOffer },
            set: { offer in
                if offer == nil {
                    viewModel.dismissSourceCleanupOffer()
                }
            }
        )
    }
}

private struct DependencyConfirmation {
    var title: String
    var message: String
    var confirmTitle: String
    var confirmRole: ButtonRole?
    var action: DependencyConfirmationAction
    var repairTitle: String? = nil
    var repairRole: ButtonRole? = nil
    var repairAction: DependencyConfirmationAction? = nil
}

private enum DependencyConfirmationAction {
    case setMod(ModInfo, enabled: Bool)
    case setMods([ModInfo], enabled: Bool)
    case selectModSet(String)
}
