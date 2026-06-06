import Foundation

final class ModManagerFolderAccessCoordinator: @unchecked Sendable {
    private let folderAccess: SecurityScopedFolderAccess
    private var lastFolderAccessError: String?

    init(folderAccess: SecurityScopedFolderAccess) {
        self.folderAccess = folderAccess
    }

    var hasBookmark: Bool {
        folderAccess.hasBookmark
    }

    func saveBookmark(for url: URL) throws {
        try folderAccess.saveBookmark(for: url)
        lastFolderAccessError = nil
    }

    func perform<T>(
        state: inout ModManagerState,
        _ operation: () throws -> T
    ) throws -> T {
        do {
            let result = try folderAccess.withAccess(operation)
            lastFolderAccessError = nil
            return result
        } catch let error as SecurityScopedFolderAccessError {
            recordFolderAccessProblem(error, in: &state)
            throw error
        }
    }

    func performIfAvailable<T>(
        state: inout ModManagerState,
        _ operation: () throws -> T
    ) -> T? {
        do {
            let result = try perform(state: &state, operation)
            lastFolderAccessError = nil
            return result
        } catch is SecurityScopedFolderAccessError {
            return nil
        } catch {
            let message = error.localizedDescription
            if lastFolderAccessError != message {
                state.activityMessage = AppStrings.Status.couldNotRestoreSavedFolderAccess(message)
                lastFolderAccessError = message
            }
            return nil
        }
    }

    private func recordFolderAccessProblem(
        _ error: SecurityScopedFolderAccessError,
        in state: inout ModManagerState
    ) {
        folderAccess.clearBookmark()
        state.hasSavedFolderAccess = false

        let message = AppStrings.Status.chooseModsFolderAgain(error.localizedDescription)
        if lastFolderAccessError != message {
            state.activityMessage = message
            lastFolderAccessError = message
        }
    }
}
