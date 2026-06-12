import SwiftUI

struct ProblemsSheet: View {
    var dependencyIssues: [ModInfo]
    var invalidFolders: [InvalidModFolder]
    var duplicateGroups: [ModDuplicateGroup]
    var smapiVersionIssues: [ModInfo]
    var detectedSMAPIVersion: String?
    var lastSessionIssues: [LastSessionModIssue]
    var lastSessionDate: Date?
    var modPageURLs: [String: URL]
    var canStartBisection: Bool
    var canManageMods: Bool
    var resolveDuplicates: (String) -> Void
    var disableMod: (ModInfo) -> Void
    var startBisection: () -> Void
    var close: () -> Void

    private var hasProblems: Bool {
        !dependencyIssues.isEmpty
            || !invalidFolders.isEmpty
            || !duplicateGroups.isEmpty
            || !smapiVersionIssues.isEmpty
            || !lastSessionIssues.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppStrings.Problems.title)
                .font(.title3)
                .fontWeight(.semibold)

            List {
                if !hasProblems {
                    ContentUnavailableView(
                        AppStrings.Problems.noProblems,
                        systemImage: "checkmark.circle"
                    )
                }

                lastSessionSection
                smapiVersionSection
                dependencyIssuesSection
                invalidFoldersSection
                duplicateGroupsSection
            }
            .frame(minHeight: 320)

            HStack {
                Button {
                    startBisection()
                } label: {
                    Label(AppStrings.Problems.findProblemMod, systemImage: "stethoscope")
                }
                .disabled(!canStartBisection)
                .help(AppStrings.Bisection.instructions)

                Spacer()
            }

            SheetCloseButton(close: close)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 460)
    }

    @ViewBuilder
    private var lastSessionSection: some View {
        if !lastSessionIssues.isEmpty {
            Section {
                ForEach(lastSessionIssues) { issue in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.mod.displayName)
                                .fontWeight(.semibold)
                            if let skippedReason = issue.skippedReason {
                                Text(AppStrings.Problems.skippedLastSession(skippedReason))
                                    .foregroundStyle(.secondary)
                            }
                            if issue.errorCount > 0 {
                                Text(AppStrings.Problems.lastSessionErrors(count: issue.errorCount))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if issue.mod.isEnabled {
                            Button(AppStrings.Problems.disable) {
                                disableMod(issue.mod)
                            }
                            .disabled(!canManageMods)
                        }
                    }
                }
            } header: {
                Text(AppStrings.Problems.lastSessionSection)
            } footer: {
                if let lastSessionDate {
                    Text(
                        AppStrings.Problems.fromGameSession(
                            lastSessionDate.formatted(date: .abbreviated, time: .shortened)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var smapiVersionSection: some View {
        if !smapiVersionIssues.isEmpty, let detectedSMAPIVersion {
            Section(AppStrings.Problems.smapiCompatibilitySection) {
                ForEach(smapiVersionIssues) { mod in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mod.displayName)
                            .fontWeight(.semibold)
                        Text(
                            AppStrings.Problems.requiresNewerSMAPI(
                                minimumVersion: mod.manifest?.minimumApiVersion?.trimmedNonEmpty ?? "",
                                installedVersion: detectedSMAPIVersion
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dependencyIssuesSection: some View {
        if !dependencyIssues.isEmpty {
            Section(AppStrings.Problems.dependenciesSection) {
                ForEach(dependencyIssues) { mod in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mod.displayName)
                            .fontWeight(.semibold)
                        if let required = mod.missingRequiredDependenciesText {
                            Text(required)
                                .foregroundStyle(.secondary)
                        }
                        if let optional = mod.missingOptionalDependenciesText {
                            Text(optional)
                                .foregroundStyle(.secondary)
                        }

                        let missingLinks = missingDependencyLinks(for: mod)
                        if !missingLinks.isEmpty {
                            HStack(spacing: 12) {
                                ForEach(missingLinks, id: \.url) { link in
                                    Link(
                                        AppStrings.Problems.getMod(link.displayName),
                                        destination: link.url
                                    )
                                    .font(.callout)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func missingDependencyLinks(for mod: ModInfo) -> [(displayName: String, url: URL)] {
        var seenIDs: Set<String> = []
        return (mod.missingRequiredDependencies + mod.missingOptionalDependencies)
            .filter { $0.problem == .missing }
            .compactMap { resolution in
                let normalizedID = resolution.requirement.normalizedUniqueID
                guard !seenIDs.contains(normalizedID),
                      let url = modPageURLs[normalizedID]
                else {
                    return nil
                }

                seenIDs.insert(normalizedID)
                return (resolution.displayName, url)
            }
    }

    @ViewBuilder
    private var invalidFoldersSection: some View {
        if !invalidFolders.isEmpty {
            Section(AppStrings.Problems.invalidFoldersSection) {
                ForEach(invalidFolders) { folder in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(folder.folderName)
                            .fontWeight(.semibold)
                        Text(folder.reason)
                            .foregroundStyle(.secondary)
                        Text(folder.url.path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var duplicateGroupsSection: some View {
        if !duplicateGroups.isEmpty {
            Section(AppStrings.Problems.duplicatesSection) {
                ForEach(duplicateGroups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .fontWeight(.semibold)
                        Text(group.mods.map(\.folderName).joined(separator: ", "))
                            .foregroundStyle(.secondary)
                        Button(AppStrings.Problems.keepNewestCopy) {
                            resolveDuplicates(group.id)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}
