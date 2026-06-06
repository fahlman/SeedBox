import AppKit
import Foundation

@MainActor
final class ModManagerWorkspacePresenter {
    private let folderAccess: SecurityScopedFolderAccess
    private var lastFolderAccessError: String?

    init(folderAccess: SecurityScopedFolderAccess) {
        self.folderAccess = folderAccess
    }

    func revealModsFolder(in state: ModManagerState, install: StardewInstall) -> ModManagerState {
        if let readinessMessage = revealBlockedMessage(for: state) {
            return stateByRecording(
                readinessMessage,
                in: state
            )
        }

        return revealWithFolderAccess(
            [install.modDirectoryURL],
            failureMessage: { AppStrings.Status.couldNotRevealModsFolder($0) },
            in: state
        )
    }

    func revealArchivedModsFolder(in state: ModManagerState, install: StardewInstall) -> ModManagerState {
        do {
            try FileManager.default.createDirectory(
                at: install.archivedModsDirectoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.activateFileViewerSelecting([install.archivedModsDirectoryURL])
            return state
        } catch {
            return stateByRecording(
                AppStrings.Status.couldNotRevealArchivedMods(error.localizedDescription),
                in: state
            )
        }
    }

    func revealMod(_ mod: ModInfo, in state: ModManagerState) -> ModManagerState {
        if let readinessMessage = revealBlockedMessage(for: state) {
            return stateByRecording(
                readinessMessage,
                in: state
            )
        }

        return revealWithFolderAccess(
            [mod.url],
            failureMessage: {
                AppStrings.Status.couldNotRevealMod(mod.displayName, errorDescription: $0)
            },
            in: state
        )
    }

    private func revealBlockedMessage(for state: ModManagerState) -> String? {
        switch state.readiness {
        case .needsFolderAccess:
            return AppStrings.Status.chooseModsFolderBeforeManaging
        case .missingModsFolder:
            return AppStrings.Status.modsFolderMissingChooseAgain
        case .ready:
            return nil
        }
    }

    private func revealWithFolderAccess(
        _ urls: [URL],
        failureMessage: (String) -> String,
        in state: ModManagerState
    ) -> ModManagerState {
        do {
            try folderAccess.withAccess {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            lastFolderAccessError = nil
            return state
        } catch let error as SecurityScopedFolderAccessError {
            return stateByRecordingFolderAccessProblem(error, in: state)
        } catch {
            return stateByRecording(
                failureMessage(error.localizedDescription),
                in: state
            )
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
