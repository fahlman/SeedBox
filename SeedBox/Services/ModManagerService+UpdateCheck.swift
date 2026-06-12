import Foundation

extension ModManagerService {
    func setChecksForModUpdates(_ isEnabled: Bool) -> ModManagerState {
        stateStore.checksForModUpdates = isEnabled
        var nextState = state
        mirrorSettings(in: &nextState)
        if !isEnabled {
            nextState.availableUpdates = []
            nextState.availableSMAPIUpdate = nil
            nextState.knownModPageURLs = [:]
        }
        return commit(nextState)
    }

    func checkForModUpdates() async -> ModManagerState {
        var nextState = state
        guard stateStore.checksForModUpdates else {
            record(AppStrings.Status.enableModUpdateChecksFirst, in: &nextState)
            return commit(nextState)
        }
        guard guardCanManageMods(in: &nextState) else {
            return commit(nextState)
        }

        var queries = nextState.mods.compactMap { mod -> ModUpdateQuery? in
            guard let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty else {
                return nil
            }

            return ModUpdateQuery(
                uniqueID: uniqueID,
                installedVersion: mod.manifest?.version?.trimmedNonEmpty,
                updateKeys: mod.manifest?.updateKeys ?? []
            )
        }
        guard !queries.isEmpty else {
            record(AppStrings.Status.noModsToCheckForUpdates, in: &nextState)
            return commit(nextState)
        }

        // SMAPI itself is checked through the same API as a synthetic entry,
        // using the version derived from its bundled mods.
        let detectedSMAPIVersion = nextState.detectedSMAPIVersion
        if let detectedSMAPIVersion {
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
        for dependencyID in missingDependencyIDs(in: nextState.mods).sorted()
        where !queriedIDs.contains(dependencyID.normalizedDependencyID) {
            queries.append(
                ModUpdateQuery(uniqueID: dependencyID, installedVersion: nil, updateKeys: [])
            )
        }

        do {
            let results = try await updateChecker.checkForUpdates(
                queries,
                apiVersion: detectedSMAPIVersion
            )

            // The await suspended this actor; start from the current state.
            var nextState = state
            let updates = availableUpdates(from: results, mods: nextState.mods)
            nextState.availableUpdates = updates
            for result in results {
                guard let pageURL = result.pageURL else {
                    continue
                }

                nextState.knownModPageURLs[result.uniqueID.normalizedDependencyID] = pageURL
            }
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
