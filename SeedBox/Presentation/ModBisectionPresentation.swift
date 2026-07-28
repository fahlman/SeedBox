import Foundation

struct ModBisectionPresentation: Equatable, Sendable {
    var stepSummary: String
    var enabledForTestNames: [String]
    var disabledForTestNames: [String]
    var remainingSuspectNames: [String]
    var nextAction: String
    var endingExplanation: String
    var safetyNote: String

    init(session: ModBisectionSession, mods: [ModInfo]) {
        let namesByToken = Dictionary(
            uniqueKeysWithValues: mods.map {
                ($0.enabledFolderName.normalizedFolderToken, $0.displayName)
            }
        )
        let testingTokens = Set(session.testingTokens)
        let disabledTokens = session.originalEnabledTokens.filter {
            !testingTokens.contains($0)
        }

        stepSummary = AppStrings.Bisection.stepSummary(
            step: session.step,
            estimatedTotalSteps: session.estimatedTotalSteps,
            suspectCount: session.candidateTokens.count,
            testingCount: session.testingTokens.count
        )
        enabledForTestNames = session.testingTokens.map {
            Self.name(for: $0, namesByToken: namesByToken)
        }
        disabledForTestNames = disabledTokens.map {
            Self.name(for: $0, namesByToken: namesByToken)
        }
        remainingSuspectNames = session.candidateTokens.map {
            Self.name(for: $0, namesByToken: namesByToken)
        }
        nextAction = AppStrings.Bisection.nextAction
        endingExplanation = AppStrings.Bisection.endingExplanation
        safetyNote = AppStrings.Bisection.safetyNote
    }

    private static func name(
        for token: String,
        namesByToken: [String: String]
    ) -> String {
        namesByToken[token] ?? token
    }
}
