import SwiftUI

enum ModManagerTabPreferences {
    static let alwaysShowTabBarKey = "alwaysShowModSetTabBar"
}

struct ModManagerWindow: View {
    @StateObject private var viewModel = ModManagerViewModel()
    @SceneStorage("modManager.openModSetTabIDs") private var openModSetTabIDsStorage = "[]"
    @SceneStorage("modManager.selectedModSetTabID") private var selectedModSetTabID = ModSetStore.defaultSetID
    @SceneStorage("modManager.modSetTabStates") private var modSetTabStatesStorage = "{}"
    @AppStorage(ModManagerTabPreferences.alwaysShowTabBarKey) private var alwaysShowTabBar = false
    @State private var restoredWindowTabs = false

    var body: some View {
        Group {
            if showsTabBar {
                TabView(selection: selectedTabBinding) {
                    ForEach(openModSetTabIDs, id: \.self) { modSetID in
                        ModManagerView(
                            viewModel: viewModel,
                            searchText: searchTextBinding(for: modSetID),
                            selectedModIDs: selectedModIDsBinding(for: modSetID)
                        )
                            .tabItem {
                                Label(
                                    tabTitle(for: modSetID),
                                    systemImage: tabSystemImage(for: modSetID)
                                )
                            }
                            .tag(modSetID)
                    }
                }
            } else {
                ModManagerView(
                    viewModel: viewModel,
                    searchText: searchTextBinding(for: selectedOpenModSetTabID),
                    selectedModIDs: selectedModIDsBinding(for: selectedOpenModSetTabID)
                )
            }
        }
        .task {
            restoreWindowTabsIfNeeded()
            await viewModel.refresh()
            synchronizeTabsWithAvailableModSets()
        }
        .onChange(of: viewModel.state.selectedModSetID) { _, selectedModSetID in
            openTabIfNeeded(selectedModSetID)
            selectedModSetTabID = selectedModSetID
        }
        .onChange(of: viewModel.state.modSets) {
            synchronizeTabsWithAvailableModSets()
        }
    }

    private var showsTabBar: Bool {
        alwaysShowTabBar || openModSetTabIDs.count > 1
    }

    private var selectedTabBinding: Binding<String> {
        Binding(
            get: { selectedOpenModSetTabID },
            set: { selectedModSetID in
                selectTab(selectedModSetID)
            }
        )
    }

    private var selectedOpenModSetTabID: String {
        let tabIDs = openModSetTabIDs
        if tabIDs.contains(selectedModSetTabID) {
            return selectedModSetTabID
        }

        return tabIDs.first ?? ModSetStore.defaultSetID
    }

    private var openModSetTabIDs: [String] {
        let decodedIDs = Self.decodeTabIDs(openModSetTabIDsStorage)
        return decodedIDs.isEmpty ? [selectedModSetTabID] : decodedIDs
    }

    private func restoreWindowTabsIfNeeded() {
        guard !restoredWindowTabs else {
            return
        }

        let tabIDs = openModSetTabIDs
        if !tabIDs.contains(selectedModSetTabID) {
            selectedModSetTabID = tabIDs.first ?? ModSetStore.defaultSetID
        }

        viewModel.restoreWindowSelectedModSet(id: selectedModSetTabID)
        restoredWindowTabs = true
    }

    private func selectTab(_ modSetID: String) {
        guard selectedModSetTabID != modSetID
                || viewModel.state.modSetSelection.appliedSetID != modSetID
        else {
            return
        }

        openTabIfNeeded(modSetID)
        selectedModSetTabID = modSetID
        Task {
            await viewModel.selectModSet(id: modSetID)
        }
    }

    private func openTabIfNeeded(_ modSetID: String) {
        guard !openModSetTabIDs.contains(modSetID) else {
            return
        }

        setOpenModSetTabIDs(openModSetTabIDs + [modSetID])
    }

    private func synchronizeTabsWithAvailableModSets() {
        let availableIDs = Set(viewModel.state.modSets.map(\.id))
        guard !availableIDs.isEmpty else {
            return
        }

        var synchronizedIDs = openModSetTabIDs.filter { availableIDs.contains($0) }
        if synchronizedIDs.isEmpty {
            synchronizedIDs = [ModSetStore.defaultSetID]
        }

        if !synchronizedIDs.contains(selectedModSetTabID) {
            selectedModSetTabID = synchronizedIDs.first ?? ModSetStore.defaultSetID
            viewModel.restoreWindowSelectedModSet(id: selectedModSetTabID)
        }

        setOpenModSetTabIDs(synchronizedIDs)
    }

    private func searchTextBinding(for modSetID: String) -> Binding<String> {
        Binding(
            get: { tabState(for: modSetID).searchText },
            set: { searchText in
                var state = tabState(for: modSetID)
                state.searchText = searchText
                setTabState(state, for: modSetID)
            }
        )
    }

    private func selectedModIDsBinding(for modSetID: String) -> Binding<Set<String>> {
        Binding(
            get: { Set(tabState(for: modSetID).selectedModIDs) },
            set: { selectedModIDs in
                var state = tabState(for: modSetID)
                state.selectedModIDs = selectedModIDs.sorted()
                setTabState(state, for: modSetID)
            }
        )
    }

    private func tabState(for modSetID: String) -> ModSetTabState {
        modSetTabStates[modSetID] ?? ModSetTabState()
    }

    private func setTabState(_ state: ModSetTabState, for modSetID: String) {
        var states = modSetTabStates
        states[modSetID] = state
        modSetTabStatesStorage = Self.encodeTabStates(states)
    }

    private var modSetTabStates: [String: ModSetTabState] {
        Self.decodeTabStates(modSetTabStatesStorage)
    }

    private func setOpenModSetTabIDs(_ ids: [String]) {
        var seenIDs: Set<String> = []
        let uniqueIDs = ids.filter { id in
            guard !seenIDs.contains(id) else {
                return false
            }

            seenIDs.insert(id)
            return true
        }

        openModSetTabIDsStorage = Self.encodeTabIDs(uniqueIDs)

        let uniqueIDSet = Set(uniqueIDs)
        let prunedStates = modSetTabStates.filter { id, _ in
            uniqueIDSet.contains(id)
        }
        modSetTabStatesStorage = Self.encodeTabStates(prunedStates)
    }

    private func tabTitle(for modSetID: String) -> String {
        viewModel.state.modSets.first { $0.id == modSetID }?.name
            ?? fallbackTabTitle(for: modSetID)
    }

    private func fallbackTabTitle(for modSetID: String) -> String {
        switch modSetID {
        case ModSetStore.allSetID:
            return ModSetStore.allSetName
        case ModSetStore.noneSetID:
            return ModSetStore.noneSetName
        case ModSetStore.defaultSetID:
            return ModSetStore.defaultSetName
        default:
            return "Mod Set"
        }
    }

    private func tabSystemImage(for modSetID: String) -> String {
        viewModel.state.modSetSelection.appliedSetID == modSetID
            ? "checkmark.circle.fill"
            : "circle"
    }

    private static func decodeTabIDs(_ storedValue: String) -> [String] {
        guard let data = storedValue.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return ids
    }

    private static func encodeTabIDs(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids),
              let storedValue = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return storedValue
    }

    private static func decodeTabStates(_ storedValue: String) -> [String: ModSetTabState] {
        guard let data = storedValue.data(using: .utf8),
              let states = try? JSONDecoder().decode([String: ModSetTabState].self, from: data)
        else {
            return [:]
        }

        return states
    }

    private static func encodeTabStates(_ states: [String: ModSetTabState]) -> String {
        guard let data = try? JSONEncoder().encode(states),
              let storedValue = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return storedValue
    }
}

private struct ModSetTabState: Codable, Equatable {
    var searchText = ""
    var selectedModIDs: [String] = []
}

struct SettingsSceneView: View {
    @StateObject private var viewModel = ModManagerViewModel()

    var body: some View {
        SettingsView(viewModel: viewModel)
    }
}
