import SwiftUI
import UniformTypeIdentifiers

struct ModManagerView: View {
    @ObservedObject var viewModel: ModManagerViewModel
    @Binding var searchText: String
    @Binding var selectedModIDs: Set<String>
    @State private var modSetEditorMode: ModSetEditorMode?
    @State private var modPendingDeletion: ModInfo?
    @State private var modSetPendingDeletion: ModSet?
    @State private var isAddingMods = false
    @State private var isChoosingModsFolder = false
    @State private var modDropIsTargeted = false

    private static var addableModContentTypes: [UTType] {
        var contentTypes: [UTType] = [.folder]
        if let zipType = UTType(filenameExtension: "zip") {
            contentTypes.append(zipType)
        }
        return contentTypes
    }

    private var filteredMods: [ModInfo] {
        let query = ModSearchQuery(searchText)
        return viewModel.state.mods.filter { query.matches($0) }
    }

    private var selectedMod: ModInfo? {
        guard selectedModIDs.count == 1, let selectedModID = selectedModIDs.first else {
            return nil
        }

        return filteredMods.first { $0.id == selectedModID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.state.readiness.canManageMods {
                ModList(
                    mods: filteredMods,
                    viewModel: viewModel,
                    selectedModIDs: $selectedModIDs,
                    selectedMod: selectedMod,
                    addMods: addMods,
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
        .background(.background)
        .overlay {
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
        .dropDestination(for: URL.self) { urls, _ in
            installDroppedMods(from: urls)
        } isTargeted: { isTargeted in
            modDropIsTargeted = isTargeted
        }
        .toolbar {
            ModManagerToolbar(
                viewModel: viewModel,
                selectedMod: selectedMod,
                createModSet: createModSet,
                duplicateSelectedModSet: duplicateSelectedModSet,
                renameSelectedModSet: renameSelectedModSet,
                deleteSelectedModSet: requestDeleteSelectedModSet,
                addMods: addMods,
                revealSelectedMod: revealSelectedMod,
                deleteSelectedMod: requestDeleteSelectedMod
            )
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
            Text("Move \(mod.displayName) to the Trash?")
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
            Text("Remove the saved mod set \(set.name)?")
        }
        .focusedValue(\.modManagerCommandContext, commandContext)
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
}
