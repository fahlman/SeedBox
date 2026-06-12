import AppKit
import SwiftUI

struct ModManagerWindow: View {
    private let viewModel = ModManagerViewModel.shared
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
            await restoreWindowStateIfNeeded()
            await viewModel.refresh()
            synchronizeSelectedModSetWithAvailableSets()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            // Catches state written while Seed Box stayed open in the
            // background — most importantly the SMAPI log from a game session
            // that just ended.
            Task {
                await viewModel.refreshAfterActivation()
            }
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

    private func restoreWindowStateIfNeeded() async {
        guard !restoredWindowState else {
            return
        }

        await viewModel.restoreSelectedModSet(id: selectedModSetID)
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
        let restoredID = selectedModSetID
        Task {
            await viewModel.restoreSelectedModSet(id: restoredID)
        }
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
    var body: some View {
        SettingsView(viewModel: ModManagerViewModel.shared)
    }
}
