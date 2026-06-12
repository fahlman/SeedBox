import Foundation

enum AddedModSource {
    case selectedSources([URL])
    case startupScan
    case watchedFolder

    var details: [String: String] {
        switch self {
        case .selectedSources(let urls):
            return [
                "source": "selected_sources",
                "source_paths": urls.map(\.path).joined(separator: "\n")
            ]
        case .startupScan:
            return [
                "source": "startup_scan"
            ]
        case .watchedFolder:
            return [
                "source": "watched_folder"
            ]
        }
    }
}

extension ModManagerService {
    func reconcileAddedMods(
        installedURLs: [URL],
        source: AddedModSource,
        shouldEnable: Bool,
        in state: ModManagerState
    ) -> ModManagerState {
        let installedTokens = Set(installedURLs.map { $0.lastPathComponent.normalizedFolderToken })
        let refreshedState = refreshedState(from: state)
        let addedMods = refreshedState.mods.filter { mod in
            installedTokens.contains(mod.enabledFolderName.normalizedFolderToken)
        }

        return reconcileAddedMods(
            addedMods,
            fallbackURLs: installedURLs,
            source: source,
            shouldEnable: shouldEnable,
            in: refreshedState
        )
    }

    func reconcileInstallResult(
        _ installResult: ModInstallResult,
        source: AddedModSource,
        shouldEnable: Bool,
        sourceCleanupSettings: SourceCleanupSettings,
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        let installedTokens = Set(
            installResult.installed
                .map(\.destinationURL.lastPathComponent)
                .map(\.normalizedFolderToken)
        )
        var changeMessage = installSummary(for: installResult)
        var changeSeverity = StatusEvent.Severity.info
        let failedConfigNames = installResult.updated
            .filter(\.configPreservationFailed)
            .map(\.displayName)
        if !failedConfigNames.isEmpty {
            changeMessage += " " + AppStrings.Status.couldNotPreserveConfigs(
                failedConfigNames.joined(separator: ", ")
            )
            changeSeverity = .error
        }

        do {
            if !installResult.installed.isEmpty {
                let currentInstall = install(for: nextState)
                try performWithFolderAccess(state: &nextState) {
                    let currentMods = try ModLibrary.scan(install: currentInstall)
                    for mod in currentMods where installedTokens.contains(mod.enabledFolderName.normalizedFolderToken) {
                        _ = try ModLibrary.setEnabled(mod, enabled: shouldEnable)
                    }
                }
            }

            nextState = refreshedState(from: nextState)
            record(changeMessage, severity: changeSeverity, in: &nextState)

            let savedState: ModManagerState
            if !installResult.installed.isEmpty {
                savedState = saveCurrentStateToSelectedModSet(
                    in: nextState,
                    recordingSuccess: AppStrings.Status.updatedModSet(
                        after: changeMessage,
                        setName: nextState.modSetSelection.selectedSetName
                    )
                )
            } else {
                savedState = nextState
            }

            var auditedState = savedState
            var details = installDetails(
                for: installResult,
                source: source,
                shouldEnable: shouldEnable
            )
            details["archive_retention_days"] = "\(auditedState.archiveSettings.normalizedRetentionDays)"
            audit(
                auditAction(for: installResult),
                summary: auditedState.activityMessage.isEmpty ? changeMessage : auditedState.activityMessage,
                subjects: auditSubjects(for: installResult),
                details: details,
                in: &auditedState
            )
            prepareSourceCleanupPresentation(
                for: installResult,
                source: source,
                importSummary: changeMessage,
                settings: sourceCleanupSettings,
                in: &auditedState
            )
            return auditedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotReconcileInstalledMods(error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func reconcileAddedMods(
        _ addedMods: [ModInfo],
        fallbackURLs: [URL],
        source: AddedModSource,
        shouldEnable: Bool,
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        let addedTokens = Set(
            (addedMods.map(\.enabledFolderName) + fallbackURLs.map(\.lastPathComponent))
                .map(\.normalizedFolderToken)
        )
        let addedCount = max(addedMods.count, fallbackURLs.count)
        let changeMessage = AppStrings.Status.addedModFolders(count: addedCount)

        do {
            try performWithFolderAccess(state: &nextState) {
                for mod in addedMods {
                    _ = try ModLibrary.setEnabled(mod, enabled: shouldEnable)
                }
            }

            nextState = refreshedState(from: nextState)
            let finalAddedURLs = finalAddedModURLs(
                matching: addedTokens,
                fallbackURLs: fallbackURLs,
                in: nextState
            )

            record(changeMessage, in: &nextState)
            var savedState = saveCurrentStateToSelectedModSet(
                in: nextState,
                recordingSuccess: AppStrings.Status.updatedModSet(
                    after: changeMessage,
                    setName: nextState.modSetSelection.selectedSetName
                )
            )
            var details = source.details
            details["installed_state"] = shouldEnable ? "enabled" : "disabled"
            details["destination_paths"] = finalAddedURLs.map(\.path).joined(separator: "\n")
            audit(
                .modsAdded,
                summary: savedState.activityMessage.isEmpty ? changeMessage : savedState.activityMessage,
                subjects: finalAddedURLs.map(auditSubjectForInstalledMod),
                details: details,
                in: &savedState
            )
            return savedState
        } catch is SecurityScopedFolderAccessError {
            return nextState
        } catch {
            record(AppStrings.Status.couldNotReconcileAddedMods(error.localizedDescription), severity: .error, in: &nextState)
            return nextState
        }
    }

    func installSummary(for installResult: ModInstallResult) -> String {
        if installResult.installed.isEmpty,
           installResult.updated.isEmpty,
           installResult.skipped.count == 1,
           let skipped = installResult.skipped.first {
            switch skipped.reason {
            case .alreadyInstalled:
                return AppStrings.Status.alreadyInstalledMod(skipped.displayName)
            case .duplicateInSelection:
                return AppStrings.Status.duplicatedSelectedMod(skipped.displayName)
            }
        }

        if installResult.installed.isEmpty,
           installResult.updated.count == 1,
           installResult.skipped.isEmpty,
           let updated = installResult.updated.first {
            return AppStrings.Status.replacedMod(
                updated.displayName,
                previousVersion: updated.previousVersion,
                installedVersion: updated.installedVersion,
                replacementKind: updated.replacementKind
            )
        }

        var sentences: [String] = []
        if !installResult.installed.isEmpty {
            sentences.append(AppStrings.Status.addedModFoldersSentence(count: installResult.installed.count))
        }
        if !installResult.updated.isEmpty {
            sentences.append(AppStrings.Status.updatedModFolders(count: installResult.updated.count))
        }
        if !installResult.skipped.isEmpty {
            let alreadyInstalledCount = installResult.skipped.filter { $0.reason == .alreadyInstalled }.count
            let duplicateSelectionCount = installResult.skipped.count - alreadyInstalledCount

            if alreadyInstalledCount > 0 {
                sentences.append(AppStrings.Status.skippedAlreadyInstalledMods(count: alreadyInstalledCount))
            }
            if duplicateSelectionCount > 0 {
                sentences.append(AppStrings.Status.skippedDuplicatedSelectedMods(count: duplicateSelectionCount))
            }
        }

        guard !sentences.isEmpty else {
            return AppStrings.Status.noModFoldersInstalled
        }

        return sentences.joined(separator: " ")
    }

    func auditAction(for installResult: ModInstallResult) -> AuditLogAction {
        if !installResult.installed.isEmpty {
            return .modsAdded
        }

        if !installResult.updated.isEmpty {
            return .modsUpdated
        }

        return .modsInstallSkipped
    }

    func auditSubjects(for installResult: ModInstallResult) -> [AuditLogSubject] {
        let installedSubjects = installResult.installed.map { install in
            AuditLogSubject(
                kind: .mod,
                id: nil,
                name: install.displayName,
                path: install.destinationURL.path
            )
        }
        let updatedSubjects = installResult.updated.map { update in
            AuditLogSubject(
                kind: .mod,
                id: nil,
                name: update.displayName,
                path: update.destinationURL.path
            )
        }
        let skippedSubjects = installResult.skipped.map { skipped in
            AuditLogSubject(
                kind: .mod,
                id: nil,
                name: skipped.displayName,
                path: skipped.existingURL?.path ?? skipped.sourceURL.path
            )
        }

        return installedSubjects + updatedSubjects + skippedSubjects
    }

    func installDetails(
        for installResult: ModInstallResult,
        source: AddedModSource,
        shouldEnable: Bool
    ) -> [String: String] {
        var details = source.details
        details["installed_state"] = shouldEnable ? "enabled" : "disabled"
        details["added_count"] = "\(installResult.installed.count)"
        details["updated_count"] = "\(installResult.updated.count)"
        details["skipped_count"] = "\(installResult.skipped.count)"
        details["destination_paths"] = installResult.installedURLs.map(\.path).joined(separator: "\n")
        details["archive_paths"] = installResult.updated.map(\.archivedURL.path).joined(separator: "\n")
        details["skipped_mods"] = installResult.skipped.map { skipped in
            "\(skipped.displayName): \(skipped.reason.auditText)"
        }
        .joined(separator: "\n")
        details["version_changes"] = installResult.updated.map { update in
            "\(update.displayName): \(update.previousVersion ?? "unknown") -> \(update.installedVersion ?? "unknown")"
        }
        .joined(separator: "\n")
        details["preserved_configs"] = installResult.updated
            .filter(\.preservedConfig)
            .map(\.displayName)
            .joined(separator: "\n")
        details["config_failures"] = installResult.updated
            .filter(\.configPreservationFailed)
            .map(\.displayName)
            .joined(separator: "\n")
        return details
    }

    func addedMods(
        in currentState: ModManagerState,
        comparedTo previousState: ModManagerState
    ) -> [ModInfo] {
        let previousTokens = Set(previousState.mods.map { $0.enabledFolderName.normalizedFolderToken })
        return addedMods(in: currentState, comparedTo: previousTokens)
    }

    func addedMods(
        in currentState: ModManagerState,
        comparedTo previousTokens: Set<String>
    ) -> [ModInfo] {
        currentState.mods.filter { mod in
            !previousTokens.contains(mod.enabledFolderName.normalizedFolderToken)
        }
    }

    func finalAddedModURLs(
        matching addedTokens: Set<String>,
        fallbackURLs: [URL],
        in state: ModManagerState
    ) -> [URL] {
        let finalURLs = state.mods
            .filter { addedTokens.contains($0.enabledFolderName.normalizedFolderToken) }
            .map(\.url)

        return finalURLs.isEmpty ? fallbackURLs : finalURLs
    }
}

private extension SkippedModInstallReason {
    var auditText: String {
        switch self {
        case .alreadyInstalled:
            return "already_installed"
        case .duplicateInSelection:
            return "duplicate_in_selection"
        }
    }
}
