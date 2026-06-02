import SwiftUI
import UniformTypeIdentifiers

struct ModManagerView: View {
    @ObservedObject var viewModel: ModManagerViewModel
    @State private var searchText = ""
    @State private var modSetEditorMode: ModSetEditorMode?
    @State private var modPendingDeletion: ModInfo?
    @State private var modSetPendingDeletion: ModSet?
    @State private var selectedModIDs: Set<String> = []
    @State private var isAddingMods = false
    @State private var isChoosingModsFolder = false

    private var filteredMods: [ModInfo] {
        let query = ModSearchQuery(searchText)
        return viewModel.mods.filter { query.matches($0) }
    }

    private var selectedMod: ModInfo? {
        guard selectedModIDs.count == 1, let selectedModID = selectedModIDs.first else {
            return nil
        }

        return filteredMods.first { $0.id == selectedModID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.canManageMods {
                ModList(
                    mods: filteredMods,
                    viewModel: viewModel,
                    selectedModIDs: $selectedModIDs,
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

            if !viewModel.activityMessage.isEmpty {
                Divider()
                Text(viewModel.activityMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ModManagerToolbar(
                viewModel: viewModel,
                selectedMod: selectedMod,
                createModSet: {
                    modSetEditorMode = .create
                },
                duplicateSelectedModSet: {
                    if let selectedSet = viewModel.selectedModSetForActions {
                        modSetEditorMode = .duplicate(selectedSet)
                    }
                },
                renameSelectedModSet: {
                    if let selectedSet = viewModel.selectedEditableModSet {
                        modSetEditorMode = .rename(selectedSet)
                    }
                },
                deleteSelectedModSet: {
                    modSetPendingDeletion = viewModel.selectedDeletableModSet
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
                viewModel.addMods(from: urls)
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
                viewModel.chooseModsFolder(url)
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
                    switch mode {
                    case .create:
                        viewModel.createModSet(named: name)
                    case .duplicate:
                        viewModel.duplicateSelectedModSet(named: name)
                    case .rename:
                        viewModel.renameSelectedModSet(to: name)
                    }
                    modSetEditorMode = nil
                }
            )
        }
        .alert(
            "Delete Mod?",
            isPresented: modDeletionAlertIsPresented,
            presenting: modPendingDeletion
        ) { mod in
            Button("Delete", role: .destructive) {
                viewModel.deleteMod(mod)
                selectedModIDs.remove(mod.id)
                modPendingDeletion = nil
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
                viewModel.deleteModSet(set)
                modSetPendingDeletion = nil
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

private enum ModSetEditorMode: Identifiable {
    case create
    case duplicate(ModSet)
    case rename(ModSet)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .duplicate(let set):
            return "duplicate-\(set.id)"
        case .rename(let set):
            return "rename-\(set.id)"
        }
    }

    var title: String {
        switch self {
        case .create:
            return "New Mod Set"
        case .duplicate:
            return "Duplicate Mod Set"
        case .rename:
            return "Rename Mod Set"
        }
    }

    var actionTitle: String {
        switch self {
        case .create:
            return "Create"
        case .duplicate:
            return "Duplicate"
        case .rename:
            return "Rename"
        }
    }

    var initialName: String {
        switch self {
        case .create:
            return "New Set"
        case .duplicate(let set):
            return "\(set.name) Copy"
        case .rename(let set):
            return set.name
        }
    }
}

private struct ModSetNameSheet: View {
    var mode: ModSetEditorMode
    var onCancel: () -> Void
    var onCommit: (String) -> Void

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(
        mode: ModSetEditorMode,
        onCancel: @escaping () -> Void,
        onCommit: @escaping (String) -> Void
    ) {
        self.mode = mode
        self.onCancel = onCancel
        self.onCommit = onCommit
        _name = State(initialValue: mode.initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.headline)

            TextField("Name", text: $name)
                .focused($isNameFocused)
                .onSubmit(commit)

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(mode.actionTitle) {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            isNameFocused = true
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        guard !trimmedName.isEmpty else {
            return
        }

        onCommit(trimmedName)
    }
}

private struct ModManagerToolbar: ToolbarContent {
    @ObservedObject var viewModel: ModManagerViewModel
    var selectedMod: ModInfo?
    var createModSet: () -> Void
    var duplicateSelectedModSet: () -> Void
    var renameSelectedModSet: () -> Void
    var deleteSelectedModSet: () -> Void
    var addMods: () -> Void
    var revealSelectedMod: () -> Void
    var deleteSelectedMod: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Mod Set", selection: $viewModel.selectedModSetID) {
                ForEach(viewModel.modSets) { set in
                    Text(set.name)
                        .tag(set.id)
                }
            }
            .frame(width: 220)
            .disabled(viewModel.modSets.isEmpty || !viewModel.canManageMods)

            Button {
                createModSet()
            } label: {
                Label("New Mod Set", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .help("New Mod Set")
            .disabled(!viewModel.canManageMods)

            Button {
                viewModel.applySelectedModSet()
            } label: {
                Label("Apply Set", systemImage: "checkmark.seal")
            }
            .disabled(viewModel.modSets.isEmpty || !viewModel.canManageMods)

            Menu {
                Button {
                    duplicateSelectedModSet()
                } label: {
                    Label("Duplicate Set", systemImage: "doc.on.doc")
                }
                .disabled(viewModel.modSets.isEmpty || !viewModel.canManageMods)

                Button {
                    renameSelectedModSet()
                } label: {
                    Label("Rename Set", systemImage: "pencil")
                }
                .disabled(!viewModel.canEditSelectedModSet || !viewModel.canManageMods)

                Divider()

                Button(role: .destructive) {
                    deleteSelectedModSet()
                } label: {
                    Label("Delete Set", systemImage: "trash")
                }
                .disabled(!viewModel.canDeleteSelectedModSet || !viewModel.canManageMods)
            } label: {
                Label("Set Actions", systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
            .disabled(!viewModel.canManageMods)
        }

        ToolbarItemGroup {
            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
                addMods()
            } label: {
                Label("Add Mods", systemImage: "plus")
            }
            .disabled(!viewModel.canManageMods)

            Button {
                revealSelectedMod()
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
            }
            .disabled(selectedMod == nil || !viewModel.canManageMods)

            Button(role: .destructive) {
                deleteSelectedMod()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .disabled(selectedMod == nil || !viewModel.canManageMods)

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

private struct ModList: View {
    var mods: [ModInfo]
    @ObservedObject var viewModel: ModManagerViewModel
    @Binding var selectedModIDs: Set<String>
    var selectedMod: ModInfo?
    var addMods: () -> Void
    var revealSelectedMod: () -> Void
    var requestDeleteSelectedMod: () -> Void
    @State private var sortOrder = [KeyPathComparator(\ModTableRow.nameSortText)]

    private var rows: [ModTableRow] {
        mods.map(ModTableRow.init).sorted(using: sortOrder)
    }

    var body: some View {
        if mods.isEmpty {
            EmptyModList(viewModel: viewModel, addMods: addMods)
        } else {
            Table(rows, selection: $selectedModIDs, sortOrder: $sortOrder) {
                TableColumn("State", value: \.enabledSortText) { row in
                    Toggle(row.enabledText, isOn: Binding(
                        get: { row.mod.isEnabled },
                        set: { viewModel.setMod(row.mod, enabled: $0) }
                    ))
                    .labelsHidden()
                    .disabled(!viewModel.canManageMods)
                }
                .width(min: 76, ideal: 92, max: 110)

                TableColumn("Mod", value: \.nameSortText) { row in
                    ModNameCell(mod: row.mod)
                }

                TableColumn("Author", value: \.authorText) { row in
                    Text(row.authorText)
                        .lineLimit(1)
                }
                .width(min: 130, ideal: 170, max: 240)

                TableColumn("Type", value: \.typeText) { row in
                    Text(row.typeText)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 150, max: 180)
            }
            .contextMenu {
                Button {
                    revealSelectedMod()
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }
                .disabled(selectedMod == nil || !viewModel.canManageMods)

                Button(role: .destructive) {
                    requestDeleteSelectedMod()
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .disabled(selectedMod == nil || !viewModel.canManageMods)
            }
        }
    }
}

private struct ModTableRow: Identifiable {
    var mod: ModInfo

    var id: String {
        mod.id
    }

    var enabledText: String {
        mod.stateText
    }

    var enabledSortText: String {
        mod.isEnabled ? "0 Enabled" : "1 Disabled"
    }

    var nameSortText: String {
        "\(mod.displayName) \(mod.versionText)"
    }

    var authorText: String {
        mod.authorText
    }

    var typeText: String {
        mod.typeText
    }
}

private struct ModNameCell: View {
    var mod: ModInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(mod.displayName)
                .font(.headline)
                .lineLimit(1)

            Text(mod.versionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let missingDependenciesText = mod.missingRequiredDependenciesText {
                Label(missingDependenciesText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct EmptyModList: View {
    @ObservedObject var viewModel: ModManagerViewModel
    var addMods: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text("No mods in \(viewModel.modFolderName)")
                .font(.title3.weight(.semibold))

            Text("Add an unzipped mod folder to install it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                addMods()
            } label: {
                Label("Add Mods", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canManageMods)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

private struct SetupEmptyState: View {
    @ObservedObject var viewModel: ModManagerViewModel
    var chooseModsFolder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text(setupTitle)
                .font(.title3.weight(.semibold))

            Text(setupDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    primarySetupAction()
                } label: {
                    Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var setupTitle: String {
        if !viewModel.hasSavedFolderAccess {
            return "Choose Mods Folder"
        }
        if viewModel.isSMAPILikelyMissing {
            return "SMAPI Not Installed"
        }
        return "Create \(viewModel.modFolderName)"
    }

    private var setupDetail: String {
        if !viewModel.hasSavedFolderAccess {
            return "Select the Mods folder Seed Box should manage."
        }
        if viewModel.isSMAPILikelyMissing {
            return "No default Mods folder was found in Steam or GOG locations."
        }
        return "Seed Box manages this Mods folder directly."
    }

    private var primaryButtonTitle: String {
        if !viewModel.hasSavedFolderAccess {
            return "Choose Folder"
        }
        return "Create Folder"
    }

    private var primaryButtonIcon: String {
        if !viewModel.hasSavedFolderAccess {
            return "folder"
        }
        return "folder.badge.plus"
    }

    private func primarySetupAction() {
        if !viewModel.hasSavedFolderAccess {
            chooseModsFolder()
        } else {
            viewModel.createModFolder()
        }
    }
}

private func openSettings() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
