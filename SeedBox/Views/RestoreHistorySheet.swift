import SwiftUI

struct RestoreHistorySheet: View {
    var archivedMods: [ArchivedModInfo]
    var currentMods: [ModInfo]
    var archiveSummary: ModArchiveSummary
    var restore: ([ArchivedModInfo]) -> Void
    var deletePermanently: ([ArchivedModInfo]) -> Void
    var revealInFinder: () -> Void
    var pruneExpiredArchives: () -> Void
    var close: () -> Void

    @State private var searchText = ""
    @State private var reasonFilter = ArchivedModReasonFilter.all
    @State private var selectedArchiveIDs = Set<ArchivedModInfo.ID>()
    @State private var pendingDelete = [ArchivedModInfo]()
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if archivedMods.isEmpty {
                ContentUnavailableView(
                    AppStrings.RestoreHistory.noArchivedMods,
                    systemImage: "archivebox"
                )
                .frame(minHeight: 320)
            } else {
                archiveControls

                if filteredArchivedMods.isEmpty {
                    ContentUnavailableView(
                        AppStrings.RestoreHistory.noMatchingArchivedMods,
                        systemImage: "magnifyingglass"
                    )
                    .frame(minHeight: 320)
                } else {
                    ArchivedModsTable(
                        archivedMods: filteredArchivedMods,
                        currentMods: currentMods,
                        showsReasonColumn: true,
                        selectedArchiveIDs: $selectedArchiveIDs
                    )
                    .frame(minHeight: 320)
                    .onChange(of: filteredArchivedMods.map(\.id)) {
                        selectedArchiveIDs.formIntersection(Set(filteredArchivedMods.map(\.id)))
                    }
                }
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 780, minHeight: 520)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.RestoreHistory.title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(AppStrings.RestoreHistory.summary(
                count: archiveSummary.archivedModCount,
                size: archiveSummary.formattedSize
            ))
            .foregroundStyle(.secondary)
        }
    }

    private var archiveControls: some View {
        HStack(spacing: 12) {
            TextField(AppStrings.RestoreHistory.searchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)

            Picker(AppStrings.RestoreHistory.reasonColumn, selection: $reasonFilter) {
                ForEach(ArchivedModReasonFilter.allCases) { filter in
                    Text(filter.title)
                        .tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Spacer()

            Text(AppStrings.RestoreHistory.filteredSummary(
                count: filteredArchivedMods.count,
                total: archivedMods.count
            ))
            .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
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
            .disabled(archiveSummary.archivedModCount == 0)

            Spacer()

            SheetCloseButton(close: close)
        }
    }

    private var filteredArchivedMods: [ArchivedModInfo] {
        ArchivedModBrowser.filteredArchivedMods(
            archivedMods,
            searchText: searchText,
            reasonFilter: reasonFilter
        )
    }

    private var selectedArchivedMods: [ArchivedModInfo] {
        filteredArchivedMods.filter { selectedArchiveIDs.contains($0.id) }
    }
}
