import SwiftUI
import UniformTypeIdentifiers

struct ModManagerView: View {
    @ObservedObject var viewModel: ModManagerViewModel
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
        content
            .background(.background)
            .overlay {
                dropOverlay
            }
            .dropDestination(for: URL.self) { urls, _ in
                installDroppedMods(from: urls)
            } isTargeted: { isTargeted in
                presentation.isDropTargeted = isTargeted
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
            .sheet(item: activeSheet, content: sheetContent)
            .alert(
                presentation.alert?.title ?? AppStrings.Alerts.dependencyWarning,
                isPresented: alertIsPresented,
                presenting: presentation.alert,
                actions: alertActions,
                message: alertMessage
            )
            .onChange(of: presentationState.pendingSourceCleanupOffer?.id) {
                syncSourceCleanupOffer()
            }
            .onAppear {
                syncSourceCleanupOffer()
            }
            .focusedValue(\.modManagerCommandContext, commandContext)
    }

    @ViewBuilder
    private func sheetContent(for sheet: ModManagerSheet) -> some View {
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
                    viewModel.keepSourceFiles(
                        for: offer,
                        remembersChoice: presentation.remembersSourceCleanupChoice
                    )
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
                    viewModel.dismissSourceCleanupOffer()
                    presentation.dismissSheet()
                }
            )
        case .problems:
            ProblemsSheet(
                dependencyIssues: presentationState.problemSummary.dependencyIssues,
                invalidFolders: presentationState.problemSummary.invalidFolders,
                duplicateGroups: presentationState.problemSummary.duplicateGroups,
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
                    viewModel.dismissSourceCleanupOffer()
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
        }
    }

    @ViewBuilder
    private func alertMessage(for alert: ModManagerAlert) -> some View {
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
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if presentationState.canManageMods {
                managedContent
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
                Text(presentationState.statusLineMessage)
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
                canManageMods: presentationState.canManageMods,
                modFolderName: viewModel.modFolderName,
                selectedModIDs: $selectedModIDs,
                selectedMod: presentationState.selection.mod,
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
    private var dropOverlay: some View {
        if presentation.isDropTargeted && presentationState.canManageMods {
            Rectangle()
                .fill(Color.accentColor.opacity(0.08))
                .overlay {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
                .allowsHitTesting(false)
        }
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { presentation.alert != nil },
            set: { isPresented in
                if !isPresented {
                    presentation.dismissAlert()
                }
            }
        )
    }
}
