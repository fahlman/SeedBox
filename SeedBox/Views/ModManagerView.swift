import SwiftUI
import UniformTypeIdentifiers

struct ModManagerView: View {
    var viewModel: ModManagerViewModel
    @Binding var searchText: String
    @Binding var selectedModIDs: Set<String>
    @State var presentation = ModManagerViewPresentation()

    static var addableModContentTypes: [UTType] {
        var contentTypes: [UTType] = [.folder]
        if let zipType = UTType(filenameExtension: "zip") {
            contentTypes.append(zipType)
        }
        return contentTypes
    }

    var presentationState: ModManagerPresentationState {
        ModManagerPresentationState(
            state: viewModel.state,
            searchText: searchText,
            selectedModIDs: selectedModIDs
        )
    }

    var body: some View {
        // Built once per render pass; rebuilding it on each access would
        // reconstruct the dependency graph and re-run the search filter.
        let presentationState = presentationState

        content(presentationState)
            .background(.background)
            .overlay {
                dropOverlay(presentationState)
            }
            .dropDestination(for: URL.self) { urls, _ in
                installDroppedMods(from: urls)
            } isTargeted: { isTargeted in
                presentation.isDropTargeted = isTargeted
            }
            .toolbar {
                toolbarContent(presentationState)
            }
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: AppStrings.Search.prompt
            )
            .fileImporter(
                isPresented: $presentation.isAddingMods,
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
                isPresented: $presentation.isChoosingModsFolder,
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
            .sheet(item: activeSheet) { sheet in
                sheetContent(for: sheet, presentationState: presentationState)
            }
            .alert(
                presentation.alert?.title ?? AppStrings.Alerts.dependencyWarning,
                isPresented: alertIsPresented,
                presenting: presentation.alert,
                actions: alertActions,
                message: { alert in
                    alertMessage(for: alert, presentationState: presentationState)
                }
            )
            .onChange(of: presentationState.pendingSourceCleanupOffer?.id) {
                syncSourceCleanupOffer()
            }
            .onChange(of: presentationState.state.bisectionSession) {
                syncBisectionSheet()
            }
            .onChange(of: presentationState.state.pendingLastSessionNotice?.id) {
                syncLastSessionNotice()
            }
            .onAppear {
                syncSourceCleanupOffer()
                syncBisectionSheet()
                syncLastSessionNotice()
            }
            .focusedValue(\.modManagerCommandContext, commandContext(presentationState))
    }

    @ViewBuilder
    private func sheetContent(
        for sheet: ModManagerSheet,
        presentationState: ModManagerPresentationState
    ) -> some View {
        switch sheet {
        case .modSetEditor(let mode):
            ModSetNameSheet(
                mode: mode,
                onCancel: {
                    presentation.dismissSheet()
                },
                onCommit: { name in
                    Task {
                        await commitModSetEditor(mode: mode, name: name)
                    }
                }
            )
        case .importPreview(let preview):
            ModImportPreviewSheet(
                preview: preview,
                cancel: {
                    ModLibrary.discardImportPreview(preview)
                    presentation.dismissSheet()
                },
                install: {
                    installPreviewedMods(preview)
                }
            )
        case .sourceCleanup(let offer):
            SourceCleanupOfferSheet(
                offer: offer,
                remembersChoice: $presentation.remembersSourceCleanupChoice,
                keepFiles: {
                    Task {
                        await viewModel.keepSourceFiles(
                            for: offer,
                            remembersChoice: presentation.remembersSourceCleanupChoice
                        )
                    }
                    presentation.dismissSheet()
                },
                moveToTrash: {
                    Task {
                        await viewModel.moveSourceFilesToTrash(
                            for: offer,
                            remembersChoice: presentation.remembersSourceCleanupChoice
                        )
                        presentation.dismissSheet()
                    }
                },
                dismissNotice: {
                    Task {
                        await viewModel.dismissSourceCleanupOffer()
                    }
                    presentation.dismissSheet()
                }
            )
        case .problems:
            ProblemsSheet(
                dependencyIssues: presentationState.problemSummary.dependencyIssues,
                invalidFolders: presentationState.problemSummary.invalidFolders,
                duplicateGroups: presentationState.problemSummary.duplicateGroups,
                smapiVersionIssues: presentationState.problemSummary.smapiVersionIssues,
                detectedSMAPIVersion: presentationState.problemSummary.detectedSMAPIVersion,
                lastSessionIssues: presentationState.state.lastSessionIssues,
                lastSessionDate: presentationState.state.lastSessionReport?.generatedAt,
                modPageURLs: presentationState.state.knownModPageURLs,
                canStartBisection: presentationState.canManageMods
                    && presentationState.state.bisectionSession == nil
                    && presentationState.state.mods.filter(\.isEnabled).count >= 2,
                canManageMods: presentationState.canManageMods,
                resolveDuplicates: resolveDuplicateGroup,
                disableMod: { mod in
                    setMod(mod, enabled: false)
                },
                startBisection: startBisection,
                close: {
                    presentation.dismissSheet()
                }
            )
        case .activity:
            ActivitySheet(
                auditTrail: presentationState.auditTrail,
                close: {
                    presentation.dismissSheet()
                }
            )
        case .restoreHistory:
            RestoreHistorySheet(
                archivedMods: presentationState.state.archivedMods,
                currentMods: presentationState.state.mods,
                archiveSummary: presentationState.archiveSummary,
                restore: restoreArchivedMods,
                revealInFinder: viewModel.revealArchivedModsFolder,
                pruneExpiredArchives: pruneExpiredArchives,
                close: {
                    presentation.dismissSheet()
                }
            )
        case .modSetComparison(let comparison):
            ModSetComparisonSheet(comparison: comparison) {
                presentation.dismissSheet()
            }
        case .bisection:
            if let session = presentationState.state.bisectionSession {
                BisectionSheet(
                    session: session,
                    reportResult: { problemOccurred in
                        Task {
                            await viewModel.recordBisectionResult(problemOccurred: problemOccurred)
                        }
                    },
                    cancel: {
                        Task {
                            await viewModel.cancelBisection()
                        }
                    }
                )
            }
        }
    }

    private var activeSheet: Binding<ModManagerSheet?> {
        Binding(
            get: {
                presentation.sheet
            },
            set: { sheet in
                if sheet == nil,
                   case .sourceCleanup = presentation.sheet {
                    Task {
                        await viewModel.dismissSourceCleanupOffer()
                    }
                }
                presentation.sheet = sheet
            }
        )
    }

    @ViewBuilder
    private func alertActions(for alert: ModManagerAlert) -> some View {
        switch alert {
        case .deleteMod(let mod):
            Button(AppStrings.Common.delete, role: .destructive) {
                Task {
                    await viewModel.deleteMod(mod)
                    removeSelectedModID(mod.id)
                    presentation.dismissAlert()
                }
            }

            Button(AppStrings.Common.cancel, role: .cancel) {
                presentation.dismissAlert()
            }
        case .deleteModSet(let set):
            Button(AppStrings.Common.delete, role: .destructive) {
                Task {
                    await viewModel.deleteModSet(set)
                    presentation.dismissAlert()
                }
            }

            Button(AppStrings.Common.cancel, role: .cancel) {
                presentation.dismissAlert()
            }
        case .dependency(let confirmation):
            Button(AppStrings.Common.cancel, role: .cancel) {
                presentation.dismissAlert()
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
        case .lastSessionNotice:
            Button(AppStrings.Alerts.reviewProblems) {
                presentation.dismissAlert()
                presentation.sheet = .problems
                Task {
                    await viewModel.dismissLastSessionNotice()
                }
            }

            Button(AppStrings.Alerts.notNow, role: .cancel) {
                presentation.dismissAlert()
                Task {
                    await viewModel.dismissLastSessionNotice()
                }
            }
        }
    }

    @ViewBuilder
    private func alertMessage(
        for alert: ModManagerAlert,
        presentationState: ModManagerPresentationState
    ) -> some View {
        switch alert {
        case .deleteMod(let mod):
            Text(AppStrings.Alerts.deleteModMessage(
                mod.displayName,
                retentionDays: presentationState.archiveRetentionDays
            ))
        case .deleteModSet(let set):
            Text(AppStrings.Alerts.deleteModSetMessage(set.name))
        case .dependency(let confirmation):
            Text(confirmation.message)
        case .lastSessionNotice(let notice):
            Text(lastSessionNoticeMessage(for: notice))
        }
    }

    private func lastSessionNoticeMessage(for notice: LastSessionNotice) -> String {
        var sentences: [String] = []
        if notice.skippedModCount > 0 {
            sentences.append(AppStrings.Alerts.lastSessionSkippedMods(count: notice.skippedModCount))
        }
        if notice.erroringModCount > 0 {
            sentences.append(AppStrings.Alerts.lastSessionErroringMods(count: notice.erroringModCount))
        }
        return sentences.joined(separator: " ")
    }

    private func content(_ presentationState: ModManagerPresentationState) -> some View {
        VStack(spacing: 0) {
            if presentationState.canManageMods {
                managedContent(presentationState)
            } else {
                SetupEmptyState(
                    readiness: presentationState.readiness,
                    modFolderName: viewModel.modFolderName,
                    chooseModsFolder: chooseModsFolder,
                    createModFolder: createModFolder
                )
            }

            if !presentationState.statusLineMessage.isEmpty {
                Divider()
                HStack(spacing: 6) {
                    if presentationState.statusLineSeverity == .error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(AppStrings.Problems.title)
                    }

                    Text(presentationState.statusLineMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
    }

    private func managedContent(_ presentationState: ModManagerPresentationState) -> some View {
        HStack(spacing: 0) {
            ModList(
                mods: presentationState.filteredMods,
                canManageMods: presentationState.canManageMods,
                modFolderName: viewModel.modFolderName,
                selectedModIDs: $selectedModIDs,
                selectedMod: presentationState.selection.mod,
                availableUpdate: presentationState.state.availableUpdate(for:),
                addMods: addMods,
                requestSetModEnabled: requestSetModEnabled,
                revealSelectedMod: revealSelectedMod,
                requestDeleteSelectedMod: requestDeleteSelectedMod
            )

            if presentation.isShowingModInspector, let selectedMod = presentationState.selection.mod {
                Divider()
                ModDetailInspector(
                    mod: selectedMod,
                    dependencyStatuses: presentationState.selection.dependencyStatuses,
                    dependents: presentationState.selection.dependents,
                    previousArchivedVersion: presentationState.selection.previousArchivedVersion,
                    archivedVersions: presentationState.selection.archivedVersions,
                    duplicateGroups: presentationState.selection.duplicateGroups,
                    availableUpdate: presentationState.selection.availableUpdate,
                    dependencyPageURLs: presentationState.selection.dependencyPageURLs,
                    lastSessionIssue: presentationState.selection.lastSessionIssue,
                    archiveSummary: presentationState.archiveSummary,
                    restorePreviousVersion: restorePreviousVersion,
                    showRestoreHistory: {
                        presentation.sheet = .restoreHistory
                    },
                    revealSelectedMod: revealSelectedMod,
                    pruneExpiredArchives: pruneExpiredArchives
                )
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
            }
        }
    }

    @ViewBuilder
    private func dropOverlay(_ presentationState: ModManagerPresentationState) -> some View {
        if presentation.isDropTargeted && presentationState.canManageMods {
            Rectangle()
                .fill(Color.accentColor.opacity(0.08))
                .overlay {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { presentation.alert != nil },
            set: { isPresented in
                if !isPresented {
                    if case .lastSessionNotice = presentation.alert {
                        Task {
                            await viewModel.dismissLastSessionNotice()
                        }
                    }
                    presentation.dismissAlert()
                }
            }
        )
    }
}
