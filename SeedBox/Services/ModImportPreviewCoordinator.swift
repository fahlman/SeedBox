import Foundation

enum ModImportPreviewResult {
    case success(ModImportPreview)
    case failure(WorkspaceActionOutcome)
}

@MainActor
final class ModImportPreviewCoordinator {
    private let folderAccess: SecurityScopedFolderAccess
    private let failureReporter: FolderAccessFailureReporter

    init(folderAccess: SecurityScopedFolderAccess) {
        self.folderAccess = folderAccess
        failureReporter = FolderAccessFailureReporter(folderAccess: folderAccess)
    }

    func prepareImportPreview(
        from selectedURLs: [URL],
        install: StardewInstall,
        readiness: ModManagerReadiness
    ) -> ModImportPreviewResult {
        if let blockedMessage = readiness.managementBlockedMessage {
            return .failure(.info(blockedMessage))
        }

        guard !selectedURLs.isEmpty else {
            return .failure(.info(AppStrings.Status.chooseModFoldersOrZipArchives))
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
            failureReporter.noteSuccess()
            return .success(preview)
        } catch let error as SecurityScopedFolderAccessError {
            return .failure(.folderAccessLost(failureReporter.reportLostAccess(error)))
        } catch {
            return .failure(
                .error(AppStrings.Status.couldNotPreviewMods(error.localizedDescription))
            )
        }
    }
}
