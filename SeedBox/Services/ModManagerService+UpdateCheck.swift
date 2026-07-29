import Foundation

extension ModManagerService {
    func setChecksForModUpdates(_ isEnabled: Bool) -> ModManagerState {
        stateStore.checksForModUpdates = isEnabled
        var nextState = state
        mirrorSettings(in: &nextState)
        if !isEnabled {
            activeUpdateCheckID = nil
            nextState.availableUpdates = []
            nextState.availableSMAPIUpdate = nil
            nextState.knownModPageURLs = [:]
        }
        return commit(nextState)
    }

    func checkForModUpdates() async -> ModManagerState {
        // Any newer attempt supersedes a request currently in flight, even if
        // this attempt exits before reaching the network.
        activeUpdateCheckID = nil
        var nextState = state
        guard stateStore.checksForModUpdates else {
            record(AppStrings.Status.enableModUpdateChecksFirst, in: &nextState)
            return commit(nextState)
        }
        guard guardCanManageMods(in: &nextState) else {
            return commit(nextState)
        }

        let queries = updateQueries(in: nextState)
        guard !queries.isEmpty else {
            record(AppStrings.Status.noModsToCheckForUpdates, in: &nextState)
            return commit(nextState)
        }

        let detectedSMAPIVersion = nextState.detectedSMAPIVersion
        let requestID = UUID()
        activeUpdateCheckID = requestID

        do {
            let results = try await updateChecker.checkForUpdates(
                queries,
                apiVersion: detectedSMAPIVersion
            )

            guard activeUpdateCheckID == requestID,
                  stateStore.checksForModUpdates,
                  updateQueries(in: state) == queries
            else {
                return state
            }
            activeUpdateCheckID = nil

            // The await suspended this actor; apply results to current state.
            var nextState = state
            let updates = availableUpdates(from: results, mods: nextState.mods)
            nextState.availableUpdates = updates
            nextState.knownModPageURLs = Dictionary(
                results.compactMap { result in
                    result.pageURL.map {
                        (result.uniqueID.normalizedDependencyID, $0)
                    }
                },
                uniquingKeysWith: { _, latest in latest }
            )
            nextState.availableSMAPIUpdate = smapiUpdate(
                from: results,
                installedVersion: nextState.detectedSMAPIVersion
            )

            var messageParts = [
                updates.isEmpty
                    ? AppStrings.Status.modsUpToDate
                    : AppStrings.Status.modUpdatesAvailable(count: updates.count)
            ]
            if let smapiUpdate = nextState.smapiUpdate {
                messageParts.append(
                    AppStrings.Status.smapiUpdateAvailable(smapiUpdate.latestVersion)
                )
            }
            let changeMessage = messageParts.joined(separator: " ")
            record(changeMessage, in: &nextState)
            audit(
                .modUpdatesChecked,
                summary: changeMessage,
                subjects: updates.map { update in
                    AuditLogSubject(
                        kind: .mod,
                        id: update.modID,
                        name: update.displayName,
                        path: nil
                    )
                },
                details: [
                    "checked_count": "\(queries.count)",
                    "update_count": "\(updates.count)",
                    "smapi_installed": detectedSMAPIVersion ?? "",
                    "smapi_update": nextState.smapiUpdate?.latestVersion ?? "",
                    "versions": updates.map { update in
                        "\(update.displayName): \(update.installedVersion ?? "unknown") -> \(update.latestVersion)"
                    }
                    .joined(separator: "\n")
                ],
                in: &nextState
            )
            return commit(nextState)
        } catch {
            guard activeUpdateCheckID == requestID,
                  stateStore.checksForModUpdates,
                  updateQueries(in: state) == queries
            else {
                return state
            }
            activeUpdateCheckID = nil

            AppLog.updateCheck.error("Update check failed: \(error)")
            var nextState = state
            record(
                AppStrings.Status.couldNotCheckForModUpdates(error.localizedDescription),
                severity: .error,
                in: &nextState
            )
            return commit(nextState)
        }
    }

    private func updateQueries(in state: ModManagerState) -> [ModUpdateQuery] {
        var queries = state.mods.compactMap { mod -> ModUpdateQuery? in
            guard let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty else {
                return nil
            }

            return ModUpdateQuery(
                uniqueID: uniqueID,
                installedVersion: mod.manifest?.version?.trimmedNonEmpty,
                updateKeys: mod.manifest?.updateKeys ?? []
            )
        }

        // SMAPI itself is checked through the same API as a synthetic entry,
        // using the version derived from its bundled mods.
        if let detectedSMAPIVersion = state.detectedSMAPIVersion {
            queries.append(
                ModUpdateQuery(
                    uniqueID: SMAPIIdentifiers.smapiModID,
                    installedVersion: detectedSMAPIVersion,
                    updateKeys: [SMAPIIdentifiers.smapiUpdateKey]
                )
            )
        }

        // Missing dependencies ride along so their mod pages can be offered
        // as "Get Mod" links.
        let queriedIDs = Set(queries.map { $0.uniqueID.normalizedDependencyID })
        for dependencyID in missingDependencyIDs(in: state.mods).sorted()
        where !queriedIDs.contains(dependencyID.normalizedDependencyID) {
            queries.append(
                ModUpdateQuery(uniqueID: dependencyID, installedVersion: nil, updateKeys: [])
            )
        }
        return queries
    }

    private func missingDependencyIDs(in mods: [ModInfo]) -> Set<String> {
        Set(
            mods.flatMap { mod in
                (mod.missingRequiredDependencies + mod.missingOptionalDependencies)
                    .filter { $0.problem == .missing }
                    .compactMap { $0.requirement.uniqueID.trimmedNonEmpty }
            }
        )
    }

    private func smapiUpdate(
        from results: [ModUpdateCheckResult],
        installedVersion: String?
    ) -> ModAvailableUpdate? {
        let smapiID = SMAPIIdentifiers.smapiModID.normalizedDependencyID
        guard let result = results.first(where: {
            $0.uniqueID.normalizedDependencyID == smapiID
        }),
            let suggestedVersion = result.suggestedVersion?.trimmedNonEmpty,
            !ModVersionComparator.version(installedVersion, satisfiesMinimum: suggestedVersion)
        else {
            return nil
        }

        return ModAvailableUpdate(
            modID: smapiID,
            displayName: "SMAPI",
            installedVersion: installedVersion,
            latestVersion: suggestedVersion,
            downloadURL: result.downloadURL ?? SMAPIIdentifiers.smapiHomeURL
        )
    }

    private func availableUpdates(
        from results: [ModUpdateCheckResult],
        mods: [ModInfo]
    ) -> [ModAvailableUpdate] {
        var modsByID: [String: ModInfo] = [:]
        for mod in mods {
            guard let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
                  modsByID[uniqueID] == nil
            else {
                continue
            }

            modsByID[uniqueID] = mod
        }

        return results.compactMap { result -> ModAvailableUpdate? in
            let normalizedID = result.uniqueID.normalizedDependencyID
            guard let suggestedVersion = result.suggestedVersion?.trimmedNonEmpty,
                  let mod = modsByID[normalizedID],
                  !ModVersionComparator.version(
                    mod.manifest?.version,
                    satisfiesMinimum: suggestedVersion
                  )
            else {
                return nil
            }

            return ModAvailableUpdate(
                modID: normalizedID,
                displayName: mod.displayName,
                installedVersion: mod.manifest?.version?.trimmedNonEmpty,
                latestVersion: suggestedVersion,
                downloadURL: result.downloadURL
            )
        }
        .sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
