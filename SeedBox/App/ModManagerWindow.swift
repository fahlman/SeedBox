import AppKit
import SwiftUI

struct ModManagerWindow: View {
    private let viewModel = ModManagerViewModel.shared
    @SceneStorage("modManager.selectedLibraryItemID") private var selectedLibraryItemID = ModLibrarySelection.initialID
    @SceneStorage("modManager.searchText") private var searchText = ""
    @State private var selectedModIDs = Set<String>()
    @State private var restoredWindowState = false

    var body: some View {
        ModManagerView(
            viewModel: viewModel,
            searchText: $searchText,
            selectedLibraryItemID: $selectedLibraryItemID,
            selectedModIDs: $selectedModIDs
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
        .onChange(of: selectedLibraryItemID) {
            selectedModIDs = []
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

}

struct SettingsSceneView: View {
    var body: some View {
        SettingsView(viewModel: ModManagerViewModel.shared)
    }
}
