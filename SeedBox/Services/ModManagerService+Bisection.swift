import Foundation

extension ModManagerService {
    func startBisection() -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState) else {
            return commit(nextState)
        }
        guard nextState.bisectionSession == nil else {
            return commit(nextState)
        }

        let enabledTokens = nextState.mods
            .filter(\.isEnabled)
            .map { $0.enabledFolderName.normalizedFolderToken }
        guard var session = ModBisection.start(enabledTokens: enabledTokens) else {
            record(AppStrings.Status.bisectionNeedsMoreMods, in: &nextState)
            return commit(nextState)
        }

        do {
            nextState = try applyTestConfiguration(for: &session, in: nextState)
            if Set(session.testingTokens) == Set(session.candidateTokens) {
                nextState = try applyEnabledTokens(
                    Set(session.originalEnabledTokens),
                    in: nextState
                )
                record(
                    AppStrings.Status.bisectionNarrowedToGroup(
                        modNames(for: session.candidateTokens, in: nextState)
                    ),
                    in: &nextState
                )
                return commit(nextState)
            }
            nextState.bisectionSession = session
            record(bisectionProgressMessage(for: session), in: &nextState)
            auditBisection(
                summary: nextState.activityMessage,
                details: ["event": "started", "candidates": "\(session.candidateTokens.count)"],
                in: &nextState
            )
            return commit(nextState)
        } catch is SecurityScopedFolderAccessError {
            return commit(nextState)
        } catch {
            AppLog.bisection.error("Bisection step failed: \(error)")
            record(
                AppStrings.Status.couldNotUpdateBisection(error.localizedDescription),
                severity: .error,
                in: &nextState
            )
            return commit(nextState)
        }
    }

    func recordBisectionResult(problemOccurred: Bool) -> ModManagerState {
        var nextState = state
        guard guardCanManageMods(in: &nextState),
              let session = nextState.bisectionSession
        else {
            return commit(nextState)
        }

        do {
            switch ModBisection.narrowed(session, problemOccurred: problemOccurred) {
            case .continuing(var narrowedSession):
                nextState = try applyTestConfiguration(for: &narrowedSession, in: nextState)
                // If dependencies force every remaining suspect into the same
                // test, no further test can separate them.
                if Set(narrowedSession.testingTokens) == Set(narrowedSession.candidateTokens) {
                    return finishBisection(
                        session,
                        message: AppStrings.Status.bisectionNarrowedToGroup(
                            modNames(for: narrowedSession.candidateTokens, in: nextState)
                        ),
                        disabledTokens: [],
                        in: nextState
                    )
                }
                nextState.bisectionSession = narrowedSession
                record(bisectionProgressMessage(for: narrowedSession), in: &nextState)
                auditBisection(
                    summary: nextState.activityMessage,
                    details: [
                        "event": "narrowed",
                        "candidates": "\(narrowedSession.candidateTokens.count)"
                    ],
                    in: &nextState
                )
                return commit(nextState)
            case .identified(let identifiedToken):
                return finishBisection(
                    session,
                    message: AppStrings.Status.bisectionIdentified(
                        modNames(for: [identifiedToken], in: nextState)
                    ),
                    disabledTokens: [identifiedToken],
                    in: nextState
                )
            case .narrowedTo(let tokens):
                return finishBisection(
                    session,
                    message: AppStrings.Status.bisectionNarrowedToGroup(
                        modNames(for: tokens, in: nextState)
                    ),
                    disabledTokens: [],
                    in: nextState
                )
            case .cleared:
                return finishBisection(
                    session,
                    message: AppStrings.Status.bisectionCleared,
                    disabledTokens: [],
                    in: nextState
                )
            }
        } catch is SecurityScopedFolderAccessError {
            return commit(nextState)
        } catch {
            AppLog.bisection.error("Bisection step failed: \(error)")
            record(
                AppStrings.Status.couldNotUpdateBisection(error.localizedDescription),
                severity: .error,
                in: &nextState
            )
            return commit(nextState)
        }
    }

    func cancelBisection() -> ModManagerState {
        var nextState = state
        guard let session = nextState.bisectionSession else {
            return commit(nextState)
        }

        return finishBisection(
            session,
            message: AppStrings.Status.bisectionCancelled,
            disabledTokens: [],
            in: nextState
        )
    }

    /// Restores the original enabled states (minus any tokens that should
    /// stay disabled, such as an identified culprit) and ends the session.
    private func finishBisection(
        _ session: ModBisectionSession,
        message: String,
        disabledTokens: [String],
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        let restoredTokens = Set(session.originalEnabledTokens).subtracting(disabledTokens)

        do {
            nextState = try applyEnabledTokens(restoredTokens, in: nextState)
        } catch {
            AppLog.bisection.error("Bisection step failed: \(error)")
            record(
                AppStrings.Status.couldNotUpdateBisection(error.localizedDescription),
                severity: .error,
                in: &nextState
            )
            nextState.bisectionSession = nil
            return commit(nextState)
        }

        nextState.bisectionSession = nil
        record(message, in: &nextState)
        auditBisection(
            summary: message,
            details: [
                "event": "finished",
                "disabled": disabledTokens.joined(separator: "\n")
            ],
            in: &nextState
        )
        return commit(nextState)
    }

    /// Enables the testing half plus every required dependency it needs to
    /// load, and records which suspects ended up enabled so narrowing stays
    /// honest when dependencies drag extra candidates along.
    private func applyTestConfiguration(
        for session: inout ModBisectionSession,
        in state: ModManagerState
    ) throws -> ModManagerState {
        let enabledTokens = requiredDependencyClosure(
            of: Set(session.testingTokens),
            in: state.mods
        )
        let candidates = Set(session.candidateTokens)
        session.testingTokens = enabledTokens
            .filter { candidates.contains($0) }
            .sorted()
        return try applyEnabledTokens(enabledTokens, in: state)
    }

    /// Renames mod folders so exactly the given tokens are enabled. Unlike
    /// normal toggling, this never writes back to the selected mod set: test
    /// configurations are temporary by definition.
    private func applyEnabledTokens(
        _ enabledTokens: Set<String>,
        in state: ModManagerState
    ) throws -> ModManagerState {
        var nextState = state
        let mods = nextState.mods
        try performWithFolderAccess(state: &nextState) {
            for mod in mods {
                let shouldBeEnabled = enabledTokens.contains(mod.enabledFolderName.normalizedFolderToken)
                guard mod.isEnabled != shouldBeEnabled else {
                    continue
                }

                _ = try ModLibrary.setEnabled(mod, enabled: shouldBeEnabled)
            }
        }
        return refreshedState(from: nextState)
    }

    private func requiredDependencyClosure(
        of tokens: Set<String>,
        in mods: [ModInfo]
    ) -> Set<String> {
        var modsByUniqueID: [String: ModInfo] = [:]
        for mod in mods {
            guard let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
                  modsByUniqueID[uniqueID] == nil
            else {
                continue
            }

            modsByUniqueID[uniqueID] = mod
        }

        var closure = tokens
        var frontier = mods.filter { closure.contains($0.enabledFolderName.normalizedFolderToken) }
        while !frontier.isEmpty {
            var added: [ModInfo] = []
            for mod in frontier {
                for requirement in mod.requiredDependencyRequirements {
                    guard let dependency = modsByUniqueID[requirement.normalizedUniqueID] else {
                        continue
                    }

                    let token = dependency.enabledFolderName.normalizedFolderToken
                    if !closure.contains(token) {
                        closure.insert(token)
                        added.append(dependency)
                    }
                }
            }
            frontier = added
        }

        return closure
    }

    private func modNames(for tokens: [String], in state: ModManagerState) -> String {
        let tokenSet = Set(tokens)
        let names = state.mods
            .filter { tokenSet.contains($0.enabledFolderName.normalizedFolderToken) }
            .map(\.displayName)
        return names.isEmpty ? tokens.joined(separator: ", ") : names.joined(separator: ", ")
    }

    private func bisectionProgressMessage(for session: ModBisectionSession) -> String {
        AppStrings.Status.bisectionProgress(
            step: session.step,
            suspectCount: session.candidateTokens.count
        )
    }

    private func auditBisection(
        summary: String,
        details: [String: String],
        in state: inout ModManagerState
    ) {
        audit(.problemSearch, summary: summary, details: details, in: &state)
    }
}
