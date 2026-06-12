import Foundation

final class ModManagerFolderAccessCoordinator: @unchecked Sendable {
    private let folderAccess: SecurityScopedFolderAccess
    private let failureReporter: FolderAccessFailureReporter

    init(folderAccess: SecurityScopedFolderAccess) {
        self.folderAccess = folderAccess
        failureReporter = FolderAccessFailureReporter(folderAccess: folderAccess)
    }

    var hasBookmark: Bool {
        folderAccess.hasBookmark
    }

    func saveBookmark(for url: URL) throws {
        try folderAccess.saveBookmark(for: url)
        failureReporter.noteSuccess()
    }

    func perform<T>(
        state: inout ModManagerState,
        _ operation: () throws -> T
    ) throws -> T {
        do {
            let result = try folderAccess.withAccess(operation)
            failureReporter.noteSuccess()
            return result
        } catch let error as SecurityScopedFolderAccessError {
            state.hasSavedFolderAccess = false
            if let message = failureReporter.reportLostAccess(error) {
                state.activityStatus = StatusEvent(severity: .error, message: message)
            }
            throw error
        }
    }

    func performIfAvailable<T>(
        state: inout ModManagerState,
        _ operation: () throws -> T
    ) -> T? {
        do {
            let result = try perform(state: &state, operation)
            failureReporter.noteSuccess()
            return result
        } catch is SecurityScopedFolderAccessError {
            return nil
        } catch {
            if let message = failureReporter.reportRestoreFailure(error) {
                state.activityStatus = StatusEvent(severity: .error, message: message)
            }
            return nil
        }
    }
}
