import SwiftUI
import UniformTypeIdentifiers

struct ModManagerView: View {
    var viewModel: ModManagerViewModel
    @Binding var searchText: String
    @Binding var selectedLibraryItemID: String
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
            selectedModIDs: selectedModIDs,
            selectedLibraryItemID: selectedLibraryItemID
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
            .onChange(of: presentationState.state.modSets) {
                syncLibrarySelection(presentationState)
            }
            .onAppear {
                syncLibrarySelection(presentationState)
                syncSourceCleanupOffer()
                syncBisectionSheet()
                syncLastSessionNotice()
                syncAppShortcutRequest()
            }
            .onReceive(NotificationCenter.default.publisher(for: SeedBoxShortcutRouter.didRequestShortcutNotification)) { _ in
                syncAppShortcutRequest()
            }
            .focusedValue(\.modManagerCommandContext, commandContext(presentationState))
    }

    @ViewBuilder
    private func content(_ presentationState: ModManagerPresentationState) -> some View {
        Group {
            if presentationState.canManageMods {
                managedLibraryContent(presentationState)
            } else {
                SetupEmptyState(
                    readiness: presentationState.readiness,
                    modFolderName: viewModel.modFolderName,
                    chooseModsFolder: chooseModsFolder,
                    createModFolder: createModFolder
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !presentationState.statusLineMessage.isEmpty {
                statusLine(presentationState)
            }
        }
    }

    private func statusLine(_ presentationState: ModManagerPresentationState) -> some View {
        VStack(spacing: 0) {
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
        .background(.background)
    }

    private func managedLibraryContent(_ presentationState: ModManagerPresentationState) -> some View {
        NavigationSplitView {
            ModLibrarySidebar(
                presentationState: presentationState,
                selectedItemID: $selectedLibraryItemID,
                selectItem: selectLibraryItem(id:)
            )
        } detail: {
            managedContent(presentationState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func managedContent(_ presentationState: ModManagerPresentationState) -> some View {
        if presentationState.librarySelection.smartSet == .recentlyDeleted {
            RecentlyDeletedModsView(
                archivedMods: ModLibrarySelection.recentlyDeletedArchivedMods(in: presentationState.state),
                currentMods: presentationState.state.mods,
                restore: restoreArchivedMods,
                deletePermanently: deleteArchivedMods,
                revealInFinder: viewModel.revealArchivedModsFolder,
                pruneExpiredArchives: pruneExpiredArchives
            )
        } else if presentationState.librarySelection.isSmartModSet && presentationState.filteredMods.isEmpty {
            SmartModSetEmptyState(
                selection: presentationState.librarySelection,
                state: presentationState.state
            )
        } else {
            modListContent(presentationState)
        }
    }

    private func modListContent(_ presentationState: ModManagerPresentationState) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let includedModSetNotice = presentationState.includedModSetNotice {
                    IncludedModSetNotice(message: includedModSetNotice)
                }

                ModList(
                    mods: presentationState.filteredMods,
                    canManageMods: presentationState.canManageMods,
                    showsStateColumn: presentationState.canShowDisplayedModStates,
                    canEditModStates: presentationState.canEditDisplayedModStates,
                    modFolderName: viewModel.modFolderName,
                    selectedModIDs: $selectedModIDs,
                    selectedMod: presentationState.selection.mod,
                    availableUpdate: presentationState.state.availableUpdate(for:),
                    addMods: addMods,
                    requestSetModEnabled: requestSetModEnabled,
                    revealSelectedMod: revealSelectedMod,
                    requestDeleteSelectedMod: requestDeleteSelectedMod
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                        openRoute(.restoreHistory)
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

}

private struct IncludedModSetNotice: View {
    var message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "lock.fill")
                .imageScale(.small)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
    }
}
