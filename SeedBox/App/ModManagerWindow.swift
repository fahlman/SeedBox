import AppKit
import CoreSpotlight
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
            SeedBoxSpotlightIndexer.reindex(from: viewModel.state)
        }
        .onChange(of: viewModel.state.mods.map(\.id)) {
            // Reindex only when mods are added or removed (id is stable across
            // enable/disable), not on every toggle.
            SeedBoxSpotlightIndexer.reindex(from: viewModel.state)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            openSpotlightResult(activity)
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
            SeedBoxSpotlightIndexer.reindex(from: viewModel.state)
        }
        .onChange(of: viewModel.state.userSmartModSets) {
            synchronizeLibrarySelectionWithAvailableItems()
            SeedBoxSpotlightIndexer.reindex(from: viewModel.state)
        }
        .onChange(of: selectedLibraryItemID) {
            selectedModIDs = []
        }
        .onOpenURL { url in
            openSeedBoxSetFile(url)
        }
    }

    /// Imports a `.seedboxset` file the user double-clicked or opened with Seed
    /// Box. The view model owns security-scoped access for every import route.
    private func openSeedBoxSetFile(_ url: URL) {
        guard url.pathExtension.lowercased() == SeedBoxSetDocument.fileExtension else {
            return
        }
        Task {
            await viewModel.importModSet(fromFileAt: url)
        }
    }

    /// Routes a tapped Spotlight result to the matching in-app view.
    private func openSpotlightResult(_ activity: NSUserActivity) {
        guard
            let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
            let route = SeedBoxEntityCatalog.route(forSystemIdentifier: identifier)
        else {
            return
        }
        SeedBoxShortcutRouter.shared.request(route: route)
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
    var menuBarCompanion: MenuBarCompanionState

    var body: some View {
        SettingsView(
            viewModel: ModManagerViewModel.shared,
            menuBarCompanion: menuBarCompanion
        )
    }
}
