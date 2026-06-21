import SwiftUI

/// Guides the halve-and-test search for a problem mod across game launches.
struct BisectionSheet: View {
    var session: ModBisectionSession
    var mods: [ModInfo]
    var reportResult: (Bool) -> Void
    var cancel: () -> Void

    private var presentation: ModBisectionPresentation {
        ModBisectionPresentation(session: session, mods: mods)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(AppStrings.Bisection.title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(presentation.stepSummary)
            .fontWeight(.medium)

            labeledSection(
                title: AppStrings.Bisection.next,
                systemImage: "arrow.right.circle",
                text: presentation.nextAction
            )

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label(AppStrings.Bisection.currentTest, systemImage: "slider.horizontal.3")
                    .font(.headline)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        modList(
                            title: AppStrings.Bisection.enabledForTest,
                            systemImage: "checkmark.circle.fill",
                            names: presentation.enabledForTestNames,
                            tint: .green
                        )

                        modList(
                            title: AppStrings.Bisection.disabledForTest,
                            systemImage: "pause.circle.fill",
                            names: presentation.disabledForTestNames,
                            tint: .orange
                        )

                        modList(
                            title: AppStrings.Bisection.remainingSuspects,
                            systemImage: "questionmark.circle.fill",
                            names: presentation.remainingSuspectNames,
                            tint: .blue
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }

            Divider()

            labeledSection(
                title: AppStrings.Bisection.howThisEnds,
                systemImage: "flag.checkered",
                text: presentation.endingExplanation
            )

            labeledSection(
                title: AppStrings.Bisection.safety,
                systemImage: "arrow.uturn.backward.circle",
                text: presentation.safetyNote
            )

            HStack {
                Button(role: .cancel) {
                    cancel()
                } label: {
                    Text(AppStrings.Bisection.cancelSearch)
                }

                Spacer()

                Button {
                    reportResult(false)
                } label: {
                    Label(AppStrings.Bisection.problemGone, systemImage: "checkmark.circle")
                }

                Button {
                    reportResult(true)
                } label: {
                    Label(AppStrings.Bisection.problemStillHappens, systemImage: "exclamationmark.triangle")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560)
    }

    private func labeledSection(
        title: String,
        systemImage: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modList(
        title: String,
        systemImage: String,
        names: [String],
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(tint)

            if names.isEmpty {
                Text(AppStrings.Bisection.noMods)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
