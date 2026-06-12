import AppKit
import Foundation

/// The result of a main-actor side effect that may need to flow back into the
/// canonical state owned by the service actor.
enum WorkspaceActionOutcome {
    case completed
    case recorded(StatusEvent)
    /// The saved bookmark stopped working and was cleared; the state's
    /// folder-access flag must drop. The message is nil when the same failure
    /// was already reported.
    case folderAccessLost(String?)

    static func info(_ message: String) -> Self {
        .recorded(StatusEvent(severity: .info, message: message))
    }

    static func error(_ message: String) -> Self {
        .recorded(StatusEvent(severity: .error, message: message))
    }
}

@MainActor
final class ModManagerWorkspacePresenter {
    private let folderAccess: SecurityScopedFolderAccess
    private let failureReporter: FolderAccessFailureReporter

    init(folderAccess: SecurityScopedFolderAccess) {
        self.folderAccess = folderAccess
        failureReporter = FolderAccessFailureReporter(folderAccess: folderAccess)
    }

    func revealModsFolder(readiness: ModManagerReadiness, install: StardewInstall) -> WorkspaceActionOutcome {
        if let blockedMessage = readiness.managementBlockedMessage {
            return .info(blockedMessage)
        }

        return revealWithFolderAccess(
            [install.modDirectoryURL],
            failureMessage: { AppStrings.Status.couldNotRevealModsFolder($0) }
        )
    }

    func revealArchivedModsFolder(install: StardewInstall) -> WorkspaceActionOutcome {
        do {
            try FileManager.default.createDirectory(
                at: install.archivedModsDirectoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.activateFileViewerSelecting([install.archivedModsDirectoryURL])
            return .completed
        } catch {
            return .error(
                AppStrings.Status.couldNotRevealArchivedMods(error.localizedDescription)
            )
        }
    }

    func revealMod(_ mod: ModInfo, readiness: ModManagerReadiness) -> WorkspaceActionOutcome {
        if let blockedMessage = readiness.managementBlockedMessage {
            return .info(blockedMessage)
        }

        return revealWithFolderAccess(
            [mod.url],
            failureMessage: {
                AppStrings.Status.couldNotRevealMod(mod.displayName, errorDescription: $0)
            }
        )
    }

    private func revealWithFolderAccess(
        _ urls: [URL],
        failureMessage: (String) -> String
    ) -> WorkspaceActionOutcome {
        do {
            try folderAccess.withAccess {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            failureReporter.noteSuccess()
            return .completed
        } catch let error as SecurityScopedFolderAccessError {
            return .folderAccessLost(failureReporter.reportLostAccess(error))
        } catch {
            return .error(failureMessage(error.localizedDescription))
        }
    }
}
