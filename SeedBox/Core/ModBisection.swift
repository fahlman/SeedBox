import Foundation

/// An in-progress search for the mod causing a problem, narrowed by halving
/// the suspect set between game launches. Persisted so the search survives
/// quitting Seed Box while the game runs.
struct ModBisectionSession: Codable, Equatable, Sendable {
    /// Folder tokens of every mod that was enabled when the search started,
    /// restored when the search ends.
    var originalEnabledTokens: [String]
    /// Folder tokens still under suspicion.
    var candidateTokens: [String]
    /// The suspects enabled in the current test configuration.
    var testingTokens: [String]
    var step: Int

    var estimatedTotalSteps: Int {
        max(1, Int(ceil(log2(Double(max(1, candidateTokens.count))))) + step)
    }
}

enum ModBisectionOutcome: Equatable, Sendable {
    /// Keep testing with a new configuration.
    case continuing(ModBisectionSession)
    /// One mod remains under suspicion.
    case identified(String)
    /// The suspects can't be separated further (for example a framework and
    /// the content pack that requires it).
    case narrowedTo([String])
    /// Every suspect was cleared.
    case cleared
}

enum ModBisection {
    static func start(enabledTokens: [String]) -> ModBisectionSession? {
        let candidates = enabledTokens.sorted()
        guard candidates.count >= 2 else {
            return nil
        }

        return ModBisectionSession(
            originalEnabledTokens: candidates,
            candidateTokens: candidates,
            testingTokens: testingHalf(of: candidates),
            step: 1
        )
    }

    static func narrowed(
        _ session: ModBisectionSession,
        problemOccurred: Bool
    ) -> ModBisectionOutcome {
        let testing = Set(session.testingTokens)
        let narrowedCandidates = problemOccurred
            ? session.candidateTokens.filter { testing.contains($0) }
            : session.candidateTokens.filter { !testing.contains($0) }

        if narrowedCandidates.isEmpty {
            return .cleared
        }

        if narrowedCandidates.count == 1, let identifiedToken = narrowedCandidates.first {
            return .identified(identifiedToken)
        }

        // Dependency closure can force suspects to be tested together; when a
        // test can no longer separate them, report the remaining group.
        if narrowedCandidates == session.candidateTokens {
            return .narrowedTo(narrowedCandidates)
        }

        var nextSession = session
        nextSession.candidateTokens = narrowedCandidates
        nextSession.testingTokens = testingHalf(of: narrowedCandidates)
        nextSession.step += 1
        return .continuing(nextSession)
    }

    private static func testingHalf(of candidates: [String]) -> [String] {
        Array(candidates.prefix((candidates.count + 1) / 2))
    }
}
