import SwiftUI

struct HelpView: View {
    static let issuesURL = URL(string: "https://github.com/fahlman/SeedBox/issues")!
    static var topics: [HelpTopic] {
        [
            HelpTopic(
                id: "getting-started",
                title: AppStrings.Help.gettingStartedTitle,
                body: AppStrings.Help.gettingStartedBody,
                systemImage: "folder"
            ),
            HelpTopic(
                id: "adding-mods",
                title: AppStrings.Help.addingModsTitle,
                body: AppStrings.Help.addingModsBody,
                systemImage: "plus.app"
            ),
            HelpTopic(
                id: "mod-sets",
                title: AppStrings.Help.modSetsTitle,
                body: AppStrings.Help.modSetsBody,
                systemImage: "sidebar.left"
            ),
            HelpTopic(
                id: "updates",
                title: AppStrings.Help.updatesTitle,
                body: AppStrings.Help.updatesBody,
                systemImage: "arrow.triangle.2.circlepath"
            ),
            HelpTopic(
                id: "restore-history",
                title: AppStrings.Help.restoreHistoryTitle,
                body: AppStrings.Help.restoreHistoryBody,
                systemImage: "clock.arrow.circlepath"
            ),
            HelpTopic(
                id: "smapi-log",
                title: AppStrings.Help.smapiLogTitle,
                body: AppStrings.Help.smapiLogBody,
                systemImage: "doc.text.magnifyingglass"
            ),
            HelpTopic(
                id: "troubleshooting",
                title: AppStrings.Help.troubleshootingTitle,
                body: AppStrings.Help.troubleshootingBody,
                systemImage: "exclamationmark.triangle"
            ),
            HelpTopic(
                id: "diagnostics",
                title: AppStrings.Settings.diagnosticsSection,
                body: AppStrings.Help.diagnosticsBody,
                systemImage: "waveform.path.ecg"
            ),
            HelpTopic(
                id: "privacy",
                title: AppStrings.Help.privacyTitle,
                body: AppStrings.Help.privacyBody,
                systemImage: "hand.raised"
            )
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Self.topics) { topic in
                    helpSection(topic)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppStrings.Help.supportTitle)
                        .font(.headline)
                    Text(AppStrings.Help.supportBody)
                        .foregroundStyle(.secondary)
                    Link(AppStrings.Help.openIssues, destination: Self.issuesURL)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 480, idealHeight: 560)
        .background(.background)
    }

    private func helpSection(_ topic: HelpTopic) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: topic.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title)
                    .font(.headline)
                Text(topic.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct HelpTopic: Identifiable, Equatable {
    var id: String
    var title: String
    var body: String
    var systemImage: String
}
