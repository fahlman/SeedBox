import SwiftUI
import UniformTypeIdentifiers

struct ModManagerView: View {
    @ObservedObject var viewModel: ModManagerViewModel
    @SceneStorage("modManager.searchText") private var searchText = ""
    @SceneStorage("modManager.selectedModIDs") private var selectedModIDsStorage = "[]"
    @State private var modSetEditorMode: ModSetEditorMode?
    @State private var modPendingDeletion: ModInfo?
    @State private var modSetPendingDeletion: ModSet?
    @State private var isAddingMods = false
    @State private var isChoosingModsFolder = false

    private var filteredMods: [ModInfo] {
        let query = ModSearchQuery(searchText)
        return viewModel.state.mods.filter { query.matches($0) }
    }

    private var selectedMod: ModInfo? {
        let selectedModIDs = restoredSelectedModIDs
        guard selectedModIDs.count == 1, let selectedModID = selectedModIDs.first else {
            return nil
        }

        return filteredMods.first { $0.id == selectedModID }
    }

    private var restoredSelectedModIDs: Set<String> {
        Self.decodeSelectedModIDs(selectedModIDsStorage)
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.state.readiness.canManageMods {
                ModList(
                    mods: filteredMods,
                    viewModel: viewModel,
                    selectedModIDs: selectedModIDsBinding,
                    selectedMod: selectedMod,
                    addMods: {
                        isAddingMods = true
                    },
                    revealSelectedMod: revealSelectedMod,
                    requestDeleteSelectedMod: requestDeleteSelectedMod
                )
            } else {
                SetupEmptyState(
                    viewModel: viewModel,
                    chooseModsFolder: {
                        isChoosingModsFolder = true
                    }
                )
            }

            if !viewModel.state.activityMessage.isEmpty {
                Divider()
                Text(viewModel.state.activityMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
        }
        .background(.background)
        .task {
            await viewModel.refresh()
        }
        .toolbar {
            ModManagerToolbar(
                viewModel: viewModel,
                selectedMod: selectedMod,
                createModSet: {
                    modSetEditorMode = .create
                },
                duplicateSelectedModSet: {
                    if let selectedSet = viewModel.state.modSetSelection.selectedSet {
                        modSetEditorMode = .duplicate(selectedSet)
                    }
                },
                renameSelectedModSet: {
                    if let selectedSet = viewModel.state.modSetSelection.selectedRenamableSet {
                        modSetEditorMode = .rename(selectedSet)
                    }
                },
                deleteSelectedModSet: {
                    modSetPendingDeletion = viewModel.state.modSetSelection.selectedDeletableSet
                },
                addMods: {
                    isAddingMods = true
                },
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
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await viewModel.addMods(from: urls)
                }
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

    private var selectedModIDsBinding: Binding<Set<String>> {
        Binding(
            get: { restoredSelectedModIDs },
            set: { selectedModIDsStorage = Self.encodeSelectedModIDs($0) }
        )
    }

    private func removeSelectedModID(_ id: String) {
        var selectedIDs = restoredSelectedModIDs
        selectedIDs.remove(id)
        selectedModIDsStorage = Self.encodeSelectedModIDs(selectedIDs)
    }

    private static func decodeSelectedModIDs(_ storedValue: String) -> Set<String> {
        guard let data = storedValue.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return Set(ids)
    }

    private static func encodeSelectedModIDs(_ ids: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(ids.sorted()),
              let storedValue = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return storedValue
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
