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
                    .frame(minHeight: 260)
                    .onChange(of: filteredArchivedMods.map(\.id)) {
                        selectedArchiveIDs.formIntersection(Set(filteredArchivedMods.map(\.id)))
                    }

                    comparisonSection
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

    private var comparisonSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.RestoreHistory.comparisonHeading)
                    .font(.headline)

                if let comparison = selectedComparison {
                    comparisonContent(comparison)
                } else {
                    Text(AppStrings.RestoreHistory.comparisonSelectOne)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func comparisonContent(_ comparison: ArchivedModComparison) -> some View {
        Text(comparisonSummary(comparison))
            .font(.callout)
            .foregroundStyle(.secondary)

        if comparison.hasDifferences {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    // Empty corner cell; verbatim so it is not extracted as a
                    // localizable string.
                    Text(verbatim: "")
                    Text(AppStrings.ModInspector.archived)
                        .fontWeight(.semibold)
                    Text(AppStrings.RestoreHistory.comparisonInstalledColumn)
                        .fontWeight(.semibold)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(comparison.differences, id: \.field) { difference in
                    GridRow {
                        Text(fieldLabel(difference.field))
                            .foregroundStyle(.secondary)
                        Text(difference.archivedValue ?? AppStrings.RestoreHistory.comparisonNoValue)
                        Text(difference.installedValue ?? AppStrings.RestoreHistory.comparisonNoValue)
                    }
                    .font(.callout)
                }
            }
            .textSelection(.enabled)
        }
    }

    private var selectedComparison: ArchivedModComparison? {
        guard
            selectedArchivedMods.count == 1,
            let archived = selectedArchivedMods.first
        else {
            return nil
        }

        return ArchivedModComparison.compare(archived, against: currentMods)
    }

    private func comparisonSummary(_ comparison: ArchivedModComparison) -> String {
        switch comparison.installStatus {
        case .notInstalled:
            return AppStrings.RestoreHistory.comparisonNotInstalled
        case .installed:
            guard comparison.hasDifferences else {
                return AppStrings.RestoreHistory.comparisonMatches
            }

            switch comparison.versionRelation {
            case .archivedIsOlder:
                return AppStrings.RestoreHistory.comparisonArchivedOlder
            case .archivedIsNewer:
                return AppStrings.RestoreHistory.comparisonArchivedNewer
            case .same, .unknown:
                return AppStrings.RestoreHistory.comparisonSameVersion
            }
        }
    }

    private func fieldLabel(_ field: ArchivedModComparison.Field) -> String {
        switch field {
        case .name:
            return AppStrings.RestoreHistory.comparisonFieldName
        case .version:
            return AppStrings.RestoreHistory.versionColumn
        case .uniqueID:
            return AppStrings.RestoreHistory.comparisonFieldUniqueID
        case .updateKeys:
            return AppStrings.RestoreHistory.comparisonFieldUpdateKeys
        case .dependencies:
            return AppStrings.ModInspector.dependenciesSection
        case .contentPackFor:
            return AppStrings.RestoreHistory.comparisonFieldContentPack
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
