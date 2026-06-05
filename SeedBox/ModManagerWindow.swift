import SwiftUI

struct ModManagerWindow: View {
    @StateObject private var viewModel = ModManagerViewModel()
    @SceneStorage("modManager.selectedModSetID") private var selectedModSetID = ModSetStore.defaultSetID
    @SceneStorage("modManager.searchText") private var searchText = ""
    @SceneStorage("modManager.selectedModIDs") private var selectedModIDsStorage = "[]"
    @State private var restoredWindowState = false

    var body: some View {
        ModManagerView(
            viewModel: viewModel,
            searchText: $searchText,
            selectedModIDs: selectedModIDsBinding
        )
        .navigationTitle(windowTitle)
        .task {
            restoreWindowStateIfNeeded()
            await viewModel.refresh()
            synchronizeSelectedModSetWithAvailableSets()
        }
        .onChange(of: viewModel.state.selectedModSetID) { _, selectedModSetID in
            self.selectedModSetID = selectedModSetID
        }
        .onChange(of: viewModel.state.modSets) {
            synchronizeSelectedModSetWithAvailableSets()
        }
    }

    private var windowTitle: String {
        viewModel.state.modSetSelection.selectedSet?.name ?? AppStrings.App.name
    }

    private func restoreWindowStateIfNeeded() {
        guard !restoredWindowState else {
            return
        }

        viewModel.restoreSelectedModSet(id: selectedModSetID)
        restoredWindowState = true
    }

    private func synchronizeSelectedModSetWithAvailableSets() {
        let availableIDs = Set(viewModel.state.modSets.map(\.id))
        guard !availableIDs.isEmpty, !availableIDs.contains(selectedModSetID) else {
            return
        }

        selectedModSetID = availableIDs.contains(ModSetStore.defaultSetID)
            ? ModSetStore.defaultSetID
            : viewModel.state.modSets.first?.id ?? ModSetStore.defaultSetID
        viewModel.restoreSelectedModSet(id: selectedModSetID)
    }

    private var selectedModIDsBinding: Binding<Set<String>> {
        Binding(
            get: { Self.decodeSelectedModIDs(selectedModIDsStorage) },
            set: { selectedModIDs in
                selectedModIDsStorage = Self.encodeSelectedModIDs(selectedModIDs)
            }
        )
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
}

struct SettingsSceneView: View {
    @StateObject private var viewModel = ModManagerViewModel()

    var body: some View {
        SettingsView(viewModel: viewModel)
    }
}
