import SwiftUI

/// Guides the halve-and-test search for a problem mod across game launches.
struct BisectionSheet: View {
    var session: ModBisectionSession
    var reportResult: (Bool) -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppStrings.Bisection.title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(
                AppStrings.Bisection.stepSummary(
                    step: session.step,
                    suspectCount: session.candidateTokens.count,
                    testingCount: session.testingTokens.count
                )
            )
            .fontWeight(.medium)

            Text(AppStrings.Bisection.instructions)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        .frame(minWidth: 480)
    }
}
