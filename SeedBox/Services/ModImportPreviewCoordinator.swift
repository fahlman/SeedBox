import Foundation

enum ModImportPreviewResult {
    case success(ModImportPreviewSession)
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
    ) async -> ModImportPreviewResult {
        if let blockedMessage = readiness.managementBlockedMessage {
            return .failure(.info(blockedMessage))
        }

        guard !selectedURLs.isEmpty else {
            return .failure(.info(AppStrings.Status.chooseModFoldersOrZipArchives))
        }

        do {
            let preview = try await Task.detached(priority: .userInitiated) { [folderAccess] in
                let sourceTokens = selectedURLs.map(SecurityScopedAccessToken.init(url:))
                defer {
                    sourceTokens.forEach { $0.stop() }
                }

                return try folderAccess.withAccess {
                    try ModLibrary.previewImport(
                        from: selectedURLs,
                        into: install
                    )
                }
            }.value
            failureReporter.noteSuccess()
            return .success(ModImportPreviewSession(preview: preview))
        } catch let error as SecurityScopedFolderAccessError {
            return .failure(.folderAccessLost(failureReporter.reportLostAccess(error)))
        } catch {
            return .failure(
                .error(AppStrings.Status.couldNotPreviewMods(error.localizedDescription))
            )
        }
    }
}
