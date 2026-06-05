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

    private var filteredMods: [ModInfo] {
        let query = ModSearchQuery(searchText)
        let graph = dependencyGraph
        return viewModel.state.mods.filter { query.matches($0, in: graph) }
    }

    private var dependencyGraph: ModDependencyGraph {
        ModDependencyGraph(mods: viewModel.state.mods)
    }

    private var selectedMod: ModInfo? {
        guard selectedModIDs.count == 1, let selectedModID = selectedModIDs.first else {
            return nil
        }

        return filteredMods.first { $0.id == selectedModID }
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
                prompt: "Search Mods"
            )
            .fileImporter(
                isPresented: $isAddingMods,
                allowedContentTypes: Self.addableModContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    installMods(from: urls)
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
                    retentionDays: Int(ModArchive.retentionInterval / 86_400)
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
            if viewModel.state.readiness.canManageMods {
                ModList(
                    mods: filteredMods,
                    viewModel: viewModel,
                    selectedModIDs: $selectedModIDs,
                    selectedMod: selectedMod,
                    addMods: addMods,
                    requestSetModEnabled: requestSetModEnabled,
                    revealSelectedMod: revealSelectedMod,
                    requestDeleteSelectedMod: requestDeleteSelectedMod
                )
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

    @ViewBuilder
    private var dropOverlay: some View {
        if modDropIsTargeted && viewModel.state.readiness.canManageMods {
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
            viewModel: viewModel,
            selectedMod: selectedMod,
            selectModSet: requestSelectModSet,
            createModSet: createModSet,
            duplicateSelectedModSet: duplicateSelectedModSet,
            renameSelectedModSet: renameSelectedModSet,
            deleteSelectedModSet: requestDeleteSelectedModSet,
            addMods: addMods,
            revealSelectedMod: revealSelectedMod,
            deleteSelectedMod: requestDeleteSelectedMod
        )
    }

    private var commandContext: ModManagerCommandContext {
        ModManagerCommandContext(
            state: viewModel.state,
            selectedMod: selectedMod,
            chooseModsFolder: chooseModsFolder,
            addMods: addMods,
            refresh: {
                Task {
                    await viewModel.refresh()
                }
            },
            createModSet: createModSet,
            duplicateSelectedModSet: duplicateSelectedModSet,
            renameSelectedModSet: renameSelectedModSet,
            deleteSelectedModSet: requestDeleteSelectedModSet,
            revealModsFolder: viewModel.revealModsFolder,
            revealArchivedModsFolder: viewModel.revealArchivedModsFolder,
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

    private func requestSelectModSet(id: String) {
        guard id != viewModel.state.selectedModSetID
                || viewModel.state.appliedModSetID != id
        else {
            return
        }

        guard let set = viewModel.state.modSets.first(where: { $0.id == id }) else {
            selectModSet(id: id)
            return
        }

        let issues = dependencyGraph.issues(applying: set)
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

    private func installMods(from urls: [URL]) {
        Task {
            await viewModel.addMods(from: urls)
        }
    }

    private func installDroppedMods(from urls: [URL]) -> Bool {
        guard viewModel.state.readiness.canManageMods else {
            return false
        }

        let installableURLs = urls.filter(Self.canDropAsModSource)
        guard !installableURLs.isEmpty else {
            return false
        }

        installMods(from: installableURLs)
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
        guard let selectedSet = viewModel.state.modSetSelection.selectedSet else {
            return
        }

        modSetEditorMode = .duplicate(selectedSet)
    }

    private func renameSelectedModSet() {
        guard let selectedSet = viewModel.state.modSetSelection.selectedRenamableSet else {
            return
        }

        modSetEditorMode = .rename(selectedSet)
    }

    private func requestDeleteSelectedModSet() {
        modSetPendingDeletion = viewModel.state.modSetSelection.selectedDeletableSet
    }

    private func revealSelectedMod() {
        guard let selectedMod else {
            return
        }

        viewModel.revealMod(selectedMod)
    }

    private func requestDeleteSelectedMod() {
        modPendingDeletion = selectedMod
    }

    private func requestSetModEnabled(_ mod: ModInfo, enabled: Bool) {
        guard mod.isEnabled != enabled else {
            return
        }

        if enabled {
            let issues = dependencyGraph.requiredIssuesIfEnabled(mod)
            guard issues.isEmpty else {
                let repairMods = dependencyGraph.disabledModsSatisfying(issues)
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
            let dependents = dependencyGraph.enabledDependentsIfDisabled(mod)
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

private struct SourceCleanupOfferSheet: View {
    var offer: SourceCleanupOffer
    @Binding var remembersChoice: Bool
    var keepFiles: () -> Void
    var moveToTrash: () -> Void
    var dismissNotice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !offer.isNotificationOnly {
                Toggle(AppStrings.SourceCleanup.rememberChoice, isOn: $remembersChoice)
            }

            HStack {
                Spacer()

                if offer.isNotificationOnly {
                    Button(AppStrings.SourceCleanup.ok) {
                        dismissNotice()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(AppStrings.SourceCleanup.keepFiles, role: .cancel) {
                        keepFiles()
                    }

                    Button(AppStrings.SourceCleanup.moveToTrash, role: .destructive) {
                        moveToTrash()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    private var title: String {
        offer.isNotificationOnly
            ? AppStrings.SourceCleanup.modsAddedTitle
            : AppStrings.SourceCleanup.moveOriginalFilesToTrashTitle
    }

    private var message: String {
        if offer.isNotificationOnly {
            return [offer.importSummary, offer.cleanupSummary]
                .compactMap { $0?.trimmedNonEmpty }
                .joined(separator: "\n\n")
        }

        return "\(offer.importSummary)\n\n\(AppStrings.SourceCleanup.moveSelectedItemsQuestion(count: offer.sourceCount))"
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
