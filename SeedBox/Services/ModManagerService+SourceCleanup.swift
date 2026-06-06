import Foundation

private struct SourceTrashFailure {
    var url: URL
    var message: String
}

private struct SourceTrashResult {
    var movedURLs: [URL] = []
    var failures: [SourceTrashFailure] = []
}

extension ModManagerService {
    func moveSourceFilesToTrash(
        for offer: SourceCleanupOffer,
        in state: ModManagerState
    ) -> ModManagerState {
        var nextState = state
        nextState.pendingSourceCleanupOffer = nil

        let cleanupResult = trashSourceFiles(offer.sourceURLs)
        let summary = sourceTrashSummary(for: cleanupResult)
        auditSourceTrashResult(
            cleanupResult,
            sourceURLs: offer.sourceURLs,
            summary: summary,
            in: &nextState
        )
        return nextState
    }

    func prepareSourceCleanupPresentation(
        for installResult: ModInstallResult,
        source: AddedModSource,
        importSummary: String,
        settings: SourceCleanupSettings,
        in state: inout ModManagerState
    ) {
        guard installResult.didChangeInstalledMods,
              case .selectedSources(let selectedURLs) = source
        else {
            state.pendingSourceCleanupOffer = nil
            return
        }

        let cleanableURLs = cleanableSourceURLs(
            selectedURLs,
            excludingDescendantsOf: install(for: state).modDirectoryURL
        )
        guard !cleanableURLs.isEmpty else {
            state.pendingSourceCleanupOffer = nil
            return
        }

        if settings.moveModFilesToTrashAfterAddingMods {
            let cleanupResult = trashSourceFiles(cleanableURLs)
            let cleanupSummary = sourceTrashSummary(for: cleanupResult)
            auditSourceTrashResult(
                cleanupResult,
                sourceURLs: cleanableURLs,
                summary: cleanupSummary,
                in: &state
            )

            state.pendingSourceCleanupOffer = settings.suppressAddModsSuccessNotification
                ? nil
                : SourceCleanupOffer(
                    sourceURLs: cleanableURLs,
                    importSummary: importSummary,
                    cleanupSummary: cleanupSummary,
                    isNotificationOnly: true
                )
            return
        }

        guard !settings.suppressAddModsSuccessNotification else {
            state.pendingSourceCleanupOffer = nil
            return
        }

        state.pendingSourceCleanupOffer = SourceCleanupOffer(
            sourceURLs: cleanableURLs,
            importSummary: importSummary
        )
    }

    private func cleanableSourceURLs(
        _ sourceURLs: [URL],
        excludingDescendantsOf excludedDirectoryURL: URL
    ) -> [URL] {
        let excludedPath = standardizedPath(for: excludedDirectoryURL)
        var seenPaths: Set<String> = []
        var cleanableURLs: [URL] = []

        for sourceURL in sourceURLs {
            let sourcePath = standardizedPath(for: sourceURL)
            guard !sourcePath.isEmpty,
                  sourcePath != excludedPath,
                  !sourcePath.hasPrefix(excludedPath + "/"),
                  !seenPaths.contains(sourcePath)
            else {
                continue
            }

            seenPaths.insert(sourcePath)
            cleanableURLs.append(sourceURL)
        }

        return cleanableURLs
    }

    private func trashSourceFiles(_ sourceURLs: [URL]) -> SourceTrashResult {
        var result = SourceTrashResult()

        for sourceURL in sourceURLs {
            let token = SecurityScopedAccessToken(url: sourceURL)
            defer {
                token.stop()
            }

            do {
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    result.failures.append(
                        SourceTrashFailure(
                            url: sourceURL,
                            message: AppStrings.SourceCleanup.fileNoLongerExists
                        )
                    )
                    continue
                }

                var resultingURL: NSURL?
                try FileManager.default.trashItem(
                    at: sourceURL,
                    resultingItemURL: &resultingURL
                )
                result.movedURLs.append((resultingURL as URL?) ?? sourceURL)
            } catch {
                result.failures.append(
                    SourceTrashFailure(
                        url: sourceURL,
                        message: error.localizedDescription
                    )
                )
            }
        }

        return result
    }

    private func sourceTrashSummary(for result: SourceTrashResult) -> String {
        let movedCount = result.movedURLs.count
        let failedCount = result.failures.count

        guard movedCount > 0 else {
            return AppStrings.SourceCleanup.couldNotMoveOriginalFilesToTrash(count: failedCount)
        }

        return AppStrings.SourceCleanup.movedOriginalFilesToTrash(
            movedCount: movedCount,
            failedCount: failedCount
        )
    }

    private func auditSourceTrashResult(
        _ result: SourceTrashResult,
        sourceURLs: [URL],
        summary: String,
        in state: inout ModManagerState
    ) {
        record(summary, in: &state)
        guard !result.movedURLs.isEmpty || !result.failures.isEmpty else {
            return
        }

        audit(
            .sourceFilesMovedToTrash,
            summary: summary,
            subjects: (result.movedURLs + result.failures.map(\.url)).map(auditSubjectForSourceFile),
            details: [
                "source_paths": sourceURLs.map(\.path).joined(separator: "\n"),
                "trashed_paths": result.movedURLs.map(\.path).joined(separator: "\n"),
                "failed_paths": result.failures.map(\.url.path).joined(separator: "\n"),
                "failure_messages": result.failures.map(\.message).joined(separator: "\n")
            ],
            in: &state
        )
    }
}
