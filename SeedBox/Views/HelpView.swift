import SwiftUI

struct HelpView: View {
    static let issuesURL = URL(string: "https://github.com/fahlman/SeedBox/issues")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                helpSection(
                    AppStrings.Help.gettingStartedTitle,
                    AppStrings.Help.gettingStartedBody
                )
                helpSection(
                    AppStrings.Help.addingModsTitle,
                    AppStrings.Help.addingModsBody
                )
                helpSection(
                    AppStrings.Help.modSetsTitle,
                    AppStrings.Help.modSetsBody
                )
                helpSection(
                    AppStrings.Help.updatesTitle,
                    AppStrings.Help.updatesBody
                )
                helpSection(
                    AppStrings.Help.troubleshootingTitle,
                    AppStrings.Help.troubleshootingBody
                )
                helpSection(
                    AppStrings.Help.privacyTitle,
                    AppStrings.Help.privacyBody
                )

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

    private func helpSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
