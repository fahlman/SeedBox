import AppKit
import SwiftUI

struct ModManagerWindow: View {
    private let viewModel = ModManagerViewModel.shared
    @SceneStorage("modManager.selectedLibraryItemID") private var selectedLibraryItemID = ModLibrarySelection.defaultID
    @SceneStorage("modManager.searchText") private var searchText = ""
    @SceneStorage("modManager.selectedModIDs") private var selectedModIDsStorage = "[]"
    @State private var restoredWindowState = false

    var body: some View {
        ModManagerView(
            viewModel: viewModel,
            searchText: $searchText,
            selectedLibraryItemID: $selectedLibraryItemID,
            selectedModIDs: selectedModIDsBinding
        )
        .navigationTitle(windowTitle)
        .task {
            await restoreWindowStateIfNeeded()
            await viewModel.refresh()
            synchronizeLibrarySelectionWithAvailableItems()
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
            selectedLibraryItemID = ModLibrarySelection.modSetID(selectedModSetID)
        }
        .onChange(of: viewModel.state.modSets) {
            synchronizeLibrarySelectionWithAvailableItems()
        }
        .onChange(of: viewModel.state.userSmartModSets) {
            synchronizeLibrarySelectionWithAvailableItems()
        }
    }

    private var windowTitle: String {
        let resolvedID = ModLibrarySelection.resolvedID(
            selectedLibraryItemID,
            in: viewModel.state
        )
        return ModLibrarySelection(id: resolvedID).title(in: viewModel.state)
    }

    private func restoreWindowStateIfNeeded() async {
        guard !restoredWindowState else {
            return
        }

        if let selectedModSetID = ModLibrarySelection(id: selectedLibraryItemID).selectedModSetID {
            await viewModel.restoreSelectedModSet(id: selectedModSetID)
        }
        restoredWindowState = true
    }

    private func synchronizeLibrarySelectionWithAvailableItems() {
        let resolvedID = ModLibrarySelection.resolvedID(selectedLibraryItemID, in: viewModel.state)
        guard selectedLibraryItemID != resolvedID else {
            return
        }

        selectedLibraryItemID = resolvedID
        if let restoredID = ModLibrarySelection(id: resolvedID).selectedModSetID {
            Task {
                await viewModel.restoreSelectedModSet(id: restoredID)
            }
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
