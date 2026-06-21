import SwiftUI

struct RecentlyDeletedModsView: View {
    var archivedMods: [ArchivedModInfo]
    var currentMods: [ModInfo]
    var restore: ([ArchivedModInfo]) -> Void
    var deletePermanently: ([ArchivedModInfo]) -> Void
    var revealInFinder: () -> Void
    var pruneExpiredArchives: () -> Void

    @State private var searchText = ""
    @State private var selectedArchiveIDs = Set<ArchivedModInfo.ID>()
    @State private var pendingDelete = [ArchivedModInfo]()
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            if archivedMods.isEmpty {
                ContentUnavailableView(
                    AppStrings.Library.noRecentlyDeletedMods,
                    systemImage: "trash"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 12) {
                    TextField(AppStrings.RestoreHistory.searchPlaceholder, text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, maxWidth: 340)

                    Text(AppStrings.RestoreHistory.filteredSummary(
                        count: filteredArchivedMods.count,
                        total: archivedMods.count
                    ))
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if filteredArchivedMods.isEmpty {
                    ContentUnavailableView(
                        AppStrings.RestoreHistory.noMatchingArchivedMods,
                        systemImage: "magnifyingglass"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ArchivedModsTable(
                        archivedMods: filteredArchivedMods,
                        currentMods: currentMods,
                        showsReasonColumn: false,
                        selectedArchiveIDs: $selectedArchiveIDs
                    )
                    .onChange(of: filteredArchivedMods.map(\.id)) {
                        selectedArchiveIDs.formIntersection(Set(filteredArchivedMods.map(\.id)))
                    }
                }

                Divider()

                HStack {
                    Button {
                        restore(selectedArchivedMods)
                    } label: {
                        Label(AppStrings.RestoreHistory.restore, systemImage: "arrow.uturn.backward")
                    }
                    .disabled(selectedArchivedMods.isEmpty)

                    Button(role: .destructive) {
                        pendingDelete = selectedArchivedMods
                        isConfirmingDelete = true
                    } label: {
                        Label(AppStrings.RestoreHistory.deletePermanently, systemImage: "trash")
                    }
                    .disabled(selectedArchivedMods.isEmpty)

                    Button {
                        revealInFinder()
                    } label: {
                        Label(AppStrings.RestoreHistory.revealInFinder, systemImage: "eye")
                    }

                    Button {
                        pruneExpiredArchives()
                    } label: {
                        Label(AppStrings.RestoreHistory.pruneExpiredArchives, systemImage: "archivebox")
                    }
                    .disabled(archivedMods.isEmpty)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .confirmationDialog(
            AppStrings.RestoreHistory.deleteConfirmationTitle(count: pendingDelete.count),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(AppStrings.RestoreHistory.deletePermanently, role: .destructive) {
                deletePermanently(pendingDelete)
                pendingDelete = []
            }

            Button(AppStrings.Common.cancel, role: .cancel) {
                pendingDelete = []
            }
        } message: {
            Text(AppStrings.RestoreHistory.deleteConfirmationMessage(count: pendingDelete.count))
        }
    }

    private var filteredArchivedMods: [ArchivedModInfo] {
        ArchivedModBrowser.filteredArchivedMods(
            archivedMods,
            searchText: searchText,
            reasonFilter: .deleted
        )
    }

    private var selectedArchivedMods: [ArchivedModInfo] {
        filteredArchivedMods.filter { selectedArchiveIDs.contains($0.id) }
    }
}

struct SmartModSetEmptyState: View {
    var selection: ModLibrarySelection

    var body: some View {
        ContentUnavailableView(
            AppStrings.Library.noMatchingMods,
            systemImage: selection.systemImage
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
