import Foundation

extension ModManagerService {
    func chooseSMAPILogFolder(_ selectedURL: URL) -> ModManagerState {
        var nextState = state
        let token = SecurityScopedAccessToken(url: selectedURL)
        defer {
            token.stop()
        }

        let resolvedURL = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        do {
            try smapiLogFolderAccess.saveBookmark(for: resolvedURL)
            nextState = refreshedState(from: nextState)
            if nextState.lastSessionReport == nil {
                record(AppStrings.Status.noSMAPILogFound, in: &nextState)
            } else {
                record(AppStrings.Status.readingSMAPILogs(from: resolvedURL.path), in: &nextState)
            }
            audit(
                .logFolderSelected,
                summary: nextState.activityMessage,
                subjects: [auditSubjectForFolder(resolvedURL)],
                in: &nextState
            )
            return commit(nextState)
        } catch {
            record(
                AppStrings.Status.couldNotSaveFolderAccess(error.localizedDescription),
                severity: .error,
                in: &nextState
            )
            return commit(nextState)
        }
    }

    /// Reads the latest SMAPI log through the dedicated bookmark. Failures
    /// are silent by design: log insights are an optional layer, never a
    /// reason to interrupt mod management.
    func reloadSMAPILogReport(in state: inout ModManagerState) {
        state.hasSMAPILogFolderAccess = smapiLogFolderAccess.hasBookmark
        guard state.hasSMAPILogFolderAccess else {
            state.lastSessionReport = nil
            return
        }

        do {
            state.lastSessionReport = try smapiLogFolderAccess.withAccess { () -> SMAPILogReport? in
                guard let folderURL = try smapiLogFolderAccess.resolveBookmarkURL() else {
                    AppLog.logInsights.error("The log folder bookmark exists but resolved to nothing.")
                    return nil
                }

                return SMAPILogReader.loadReport(inLogFolder: folderURL)
            }
        } catch {
            AppLog.logInsights.error("Couldn't access the SMAPI log folder: \(error)")
            state.lastSessionReport = nil
        }
    }
}
