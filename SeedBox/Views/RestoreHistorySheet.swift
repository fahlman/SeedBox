import SwiftUI

struct RestoreHistorySheet: View {
    var archivedMods: [ArchivedModInfo]
    var currentMods: [ModInfo]
    var archiveSummary: ModArchiveSummary
    var restore: ([ArchivedModInfo]) -> Void
    var revealInFinder: () -> Void
    var pruneExpiredArchives: () -> Void
    var close: () -> Void

    @State private var selectedArchiveIDs = Set<ArchivedModInfo.ID>()

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
                Table(archivedMods, selection: $selectedArchiveIDs) {
                    TableColumn(AppStrings.RestoreHistory.modColumn) { archivedMod in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(archivedMod.displayName)
                                .fontWeight(.semibold)
                                .lineLimit(1)

                            Text(installStateText(for: archivedMod))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 180, ideal: 240, max: 320)

                    TableColumn(AppStrings.RestoreHistory.versionColumn) { archivedMod in
                        Text(archivedMod.versionText)
                    }
                    .width(min: 90, ideal: 110, max: 150)

                    TableColumn(AppStrings.RestoreHistory.reasonColumn) { archivedMod in
                        Text(reasonText(for: archivedMod))
                    }
                    .width(min: 100, ideal: 130, max: 160)

                    TableColumn(AppStrings.RestoreHistory.archivedColumn) { archivedMod in
                        Text(dateText(for: archivedMod))
                    }
                    .width(min: 150, ideal: 180, max: 230)

                    TableColumn(AppStrings.RestoreHistory.folderColumn) { archivedMod in
                        Text(archivedMod.folderName)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 320)
                .onChange(of: archivedMods.map(\.id)) {
                    selectedArchiveIDs.formIntersection(Set(archivedMods.map(\.id)))
                }
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 780, minHeight: 520)
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

    private var footer: some View {
        HStack {
            Button {
                restore(selectedArchivedMods)
            } label: {
                Label(AppStrings.RestoreHistory.restore, systemImage: "arrow.uturn.backward")
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

    private var selectedArchivedMods: [ArchivedModInfo] {
        archivedMods.filter { selectedArchiveIDs.contains($0.id) }
    }

    private func installStateText(for archivedMod: ArchivedModInfo) -> String {
        guard let currentMod = ModArchive.currentMod(for: archivedMod, in: currentMods) else {
            return AppStrings.RestoreHistory.deleted
        }

        return AppStrings.RestoreHistory.currentlyInstalled(currentMod.versionText)
    }

    private func reasonText(for archivedMod: ArchivedModInfo) -> String {
        archivedMod.reason?.displayText ?? AppStrings.ModInspector.archived
    }

    private func dateText(for archivedMod: ArchivedModInfo) -> String {
        guard let archivedDate = archivedMod.archivedDate else {
            return AppStrings.RestoreHistory.unknownDate
        }

        return archivedDate.formatted(date: .abbreviated, time: .shortened)
    }
}

private extension ModArchiveReason {
    var displayText: String {
        switch self {
        case .deleted:
            return AppStrings.RestoreHistory.deleted
        case .updated:
            return AppStrings.AuditActions.modsUpdated
        }
    }
}
