import SwiftUI

struct ProblemsSheet: View {
    var dependencyIssues: [ModInfo]
    var invalidFolders: [InvalidModFolder]
    var duplicateGroups: [ModDuplicateGroup]
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppStrings.Problems.title)
                .font(.title3)
                .fontWeight(.semibold)

            List {
                if dependencyIssues.isEmpty && invalidFolders.isEmpty && duplicateGroups.isEmpty {
                    ContentUnavailableView(
                        AppStrings.Problems.noProblems,
                        systemImage: "checkmark.circle"
                    )
                }

                dependencyIssuesSection
                invalidFoldersSection
                duplicateGroupsSection
            }
            .frame(minHeight: 320)

            SheetCloseButton(close: close)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 460)
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
                    }
                }
            }
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
                    }
                }
            }
        }
    }
}
