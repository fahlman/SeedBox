import SwiftUI

struct ModDetailInspector: View {
    var mod: ModInfo
    var dependencyStatuses: [ModDependencyStatus]
    var dependents: [ModInfo]
    var previousArchivedVersion: ArchivedModInfo?
    var archivedVersions: [ArchivedModInfo]
    var duplicateGroups: [ModDuplicateGroup]
    var availableUpdate: ModAvailableUpdate?
    var dependencyPageURLs: [String: URL]
    var lastSessionIssue: LastSessionModIssue?
    var archiveSummary: ModArchiveSummary
    var restorePreviousVersion: () -> Void
    var showRestoreHistory: () -> Void
    var revealSelectedMod: () -> Void
    var pruneExpiredArchives: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                updateSection
                lastSessionSection

                if let description = mod.descriptionText {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                detailSection(AppStrings.ModInspector.detailsSection) {
                    detailRow(AppStrings.ModInspector.state, mod.stateText)
                    detailRow(AppStrings.ModInspector.type, mod.typeText)
                    detailRow(AppStrings.ModInspector.author, mod.authorText)
                    detailRow(AppStrings.ModInspector.updateSource, mod.updateSourceText)
                    detailRow(AppStrings.ModInspector.updateKeys, mod.updateKeysText)
                    detailRow(AppStrings.ModInspector.uniqueID, mod.manifest?.uniqueID?.trimmedNonEmpty)
                    detailRow(AppStrings.ModInspector.entryDll, mod.manifest?.entryDll?.trimmedNonEmpty)
                    detailRow(AppStrings.ModInspector.minimumApiVersion, mod.manifest?.minimumApiVersion?.trimmedNonEmpty)
                    detailRow(AppStrings.ModInspector.folder, mod.folderName)
                }

                dependencySection
                dependentsSection
                duplicateSection
                archiveSection
                revealButton
            }
            .padding(16)
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mod.displayName)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(2)

            Text(mod.versionText)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var updateSection: some View {
        if let availableUpdate {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    AppStrings.ModInspector.updateAvailable(availableUpdate.latestVersion),
                    systemImage: "arrow.up.circle.fill"
                )
                .foregroundStyle(.blue)

                if let downloadURL = availableUpdate.downloadURL {
                    Link(AppStrings.ModInspector.viewUpdatePage, destination: downloadURL)
                        .font(.callout)
                }
            }
        }
    }

    @ViewBuilder
    private var lastSessionSection: some View {
        if let lastSessionIssue {
            VStack(alignment: .leading, spacing: 4) {
                if let skippedReason = lastSessionIssue.skippedReason {
                    Label(
                        AppStrings.Problems.skippedLastSession(skippedReason),
                        systemImage: "xmark.octagon.fill"
                    )
                    .foregroundStyle(.orange)
                }
                if lastSessionIssue.errorCount > 0 {
                    Label(
                        AppStrings.Problems.lastSessionErrors(count: lastSessionIssue.errorCount),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
            .font(.callout)
        }
    }

    private var revealButton: some View {
        HStack {
            Button {
                revealSelectedMod()
            } label: {
                Label(AppStrings.ModInspector.reveal, systemImage: "eye")
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var dependencySection: some View {
        detailSection(AppStrings.ModInspector.dependenciesSection) {
            if dependencyStatuses.isEmpty {
                Text(AppStrings.ModInspector.noDependencies)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(dependencyStatuses) { status in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.displayName)
                                    .lineLimit(1)
                                Text(status.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                if status.state == .missing,
                                   let pageURL = dependencyPageURLs[status.requirement.normalizedUniqueID] {
                                    Link(
                                        AppStrings.Problems.getMod(status.displayName),
                                        destination: pageURL
                                    )
                                    .font(.caption)
                                }
                            }
                        } icon: {
                            Image(systemName: status.systemImage)
                                .foregroundStyle(status.foregroundStyle)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dependentsSection: some View {
        detailSection(AppStrings.ModInspector.requiredBySection) {
            if dependents.isEmpty {
                Text(AppStrings.ModInspector.noDependents)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(dependents) { dependent in
                        Text(dependent.displayName)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var duplicateSection: some View {
        if !duplicateGroups.isEmpty {
            detailSection(AppStrings.ModInspector.duplicatesSection) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(duplicateGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(group.mods) { duplicate in
                                Text(duplicate.folderName)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var archiveSection: some View {
        detailSection(AppStrings.ModInspector.archiveSection) {
            detailRow(AppStrings.ModInspector.archivedMods, "\(archiveSummary.archivedModCount)")
            detailRow(AppStrings.ModInspector.archiveSize, archiveSummary.formattedSize)

            if let previousArchivedVersion {
                detailRow(AppStrings.ModInspector.previousVersion, previousArchivedVersion.versionText)

                HStack {
                    Button {
                        restorePreviousVersion()
                    } label: {
                        Label(AppStrings.ModInspector.restorePreviousVersion, systemImage: "arrow.uturn.backward")
                    }

                    Button {
                        showRestoreHistory()
                    } label: {
                        Label(AppStrings.RestoreHistory.title, systemImage: "clock.arrow.circlepath")
                    }
                }
            } else {
                Text(AppStrings.ModInspector.noPreviousVersion)
                    .foregroundStyle(.secondary)
            }

            if !archivedVersions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(archivedVersions.prefix(6)) { archivedMod in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(archivedMod.versionText)
                            Text(archiveDetailText(for: archivedMod))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Button {
                pruneExpiredArchives()
            } label: {
                Label(AppStrings.ModInspector.pruneExpiredArchives, systemImage: "archivebox")
            }
            .disabled(archiveSummary.archivedModCount == 0)
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value = value?.trimmedNonEmpty {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text(label)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .textSelection(.enabled)
                }
            }
            .font(.callout)
        }
    }

    private func archiveDetailText(for archivedMod: ArchivedModInfo) -> String {
        let reason = archivedMod.reason?.displayText ?? AppStrings.ModInspector.archived
        guard let archivedDate = archivedMod.archivedDate else {
            return reason
        }

        return "\(reason) - \(archivedDate.formatted(date: .abbreviated, time: .shortened))"
    }
}

private extension ModDependencyStatus {
    var systemImage: String {
        switch state {
        case .satisfied:
            return "checkmark.circle"
        case .missing:
            return "questionmark.circle"
        case .disabled:
            return "pause.circle"
        case .versionTooOld:
            return "exclamationmark.triangle"
        }
    }

    var foregroundStyle: Color {
        switch state {
        case .satisfied:
            return .green
        case .missing, .disabled, .versionTooOld:
            return .orange
        }
    }

    var detailText: String {
        var segments: [String] = [
            isRequired ? AppStrings.ModInspector.requiredDependency : AppStrings.ModInspector.optionalDependency,
            state.displayText
        ]
        if let minimumVersionText {
            segments.append(AppStrings.ModInspector.minimumVersion(minimumVersionText))
        }
        if let matchedModVersion {
            segments.append(AppStrings.ModInspector.installedVersion(matchedModVersion))
        }
        return segments.joined(separator: " • ")
    }
}

private extension ModDependencyStatusState {
    var displayText: String {
        switch self {
        case .satisfied:
            return AppStrings.ModInspector.satisfied
        case .missing:
            return AppStrings.ModInspector.missing
        case .disabled:
            return AppStrings.ModInspector.disabled
        case .versionTooOld:
            return AppStrings.ModInspector.versionTooOld
        }
    }
}

private extension ModArchiveReason {
    var displayText: String {
        switch self {
        case .deleted:
            return AppStrings.AuditActions.modDeleted
        case .updated:
            return AppStrings.AuditActions.modsUpdated
        }
    }
}
