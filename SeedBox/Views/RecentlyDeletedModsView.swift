import SwiftUI

struct RecentlyDeletedModsView: View {
    var archivedMods: [ArchivedModInfo]
    var currentMods: [ModInfo]
    var restore: ([ArchivedModInfo]) -> Void
    var revealInFinder: () -> Void
    var pruneExpiredArchives: () -> Void

    @State private var selectedArchiveIDs = Set<ArchivedModInfo.ID>()

    var body: some View {
        VStack(spacing: 0) {
            if archivedMods.isEmpty {
                ContentUnavailableView(
                    AppStrings.Library.noRecentlyDeletedMods,
                    systemImage: "trash"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                    TableColumn(AppStrings.RestoreHistory.archivedColumn) { archivedMod in
                        Text(dateText(for: archivedMod))
                    }
                    .width(min: 150, ideal: 180, max: 230)

                    TableColumn(AppStrings.RestoreHistory.folderColumn) { archivedMod in
                        Text(archivedMod.folderName)
                            .lineLimit(1)
                    }
                }
                .onChange(of: archivedMods.map(\.id)) {
                    selectedArchiveIDs.formIntersection(Set(archivedMods.map(\.id)))
                }

                Divider()

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
                    .disabled(archivedMods.isEmpty)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
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

    private func dateText(for archivedMod: ArchivedModInfo) -> String {
        guard let archivedDate = archivedMod.archivedDate else {
            return AppStrings.RestoreHistory.unknownDate
        }

        return archivedDate.formatted(date: .abbreviated, time: .shortened)
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
