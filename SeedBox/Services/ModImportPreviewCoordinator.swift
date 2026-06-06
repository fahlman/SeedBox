import Foundation

@MainActor
final class ModImportPreviewCoordinator {
    private let folderAccess: SecurityScopedFolderAccess
    private var lastFolderAccessError: String?

    init(folderAccess: SecurityScopedFolderAccess) {
        self.folderAccess = folderAccess
    }

    func prepareImportPreview(
        from selectedURLs: [URL],
        install: StardewInstall,
        state: ModManagerState
    ) -> ModImportPreviewResult {
        if let readinessMessage = importBlockedMessage(for: state) {
            return .failure(stateByRecording(readinessMessage, in: state))
        }

        guard !selectedURLs.isEmpty else {
            return .failure(
                stateByRecording(
                    AppStrings.Status.chooseModFoldersOrZipArchives,
                    in: state
                )
            )
        }

        let sourceTokens = selectedURLs.map(SecurityScopedAccessToken.init(url:))
        defer {
            sourceTokens.forEach { $0.stop() }
        }

        do {
            let preview = try folderAccess.withAccess {
                try ModLibrary.previewImport(
                    from: selectedURLs,
                    into: install
                )
            }
            lastFolderAccessError = nil
            return .success(preview, state)
        } catch let error as SecurityScopedFolderAccessError {
            return .failure(stateByRecordingFolderAccessProblem(error, in: state))
        } catch {
            return .failure(
                stateByRecording(
                    AppStrings.Status.couldNotPreviewMods(error.localizedDescription),
                    in: state
                )
            )
        }
    }

    private func importBlockedMessage(for state: ModManagerState) -> String? {
        switch state.readiness {
        case .needsFolderAccess:
            return AppStrings.Status.chooseModsFolderBeforeManaging
        case .missingModsFolder:
            return AppStrings.Status.modsFolderMissingChooseAgain
        case .ready:
            return nil
        }
    }

    private func stateByRecordingFolderAccessProblem(
        _ error: SecurityScopedFolderAccessError,
        in state: ModManagerState
    ) -> ModManagerState {
        folderAccess.clearBookmark()

        let message = AppStrings.Status.chooseModsFolderAgain(error.localizedDescription)
        var nextState = state
        nextState.hasSavedFolderAccess = false
        if lastFolderAccessError != message {
            nextState.activityMessage = message
            lastFolderAccessError = message
        }
        return nextState
    }

    private func stateByRecording(_ message: String, in state: ModManagerState) -> ModManagerState {
        var nextState = state
        nextState.activityMessage = message
        return nextState
    }
}

enum ModImportPreviewResult {
    case success(ModImportPreview, ModManagerState)
    case failure(ModManagerState)
}
