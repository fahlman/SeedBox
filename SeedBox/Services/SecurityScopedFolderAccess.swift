import Foundation

enum SecurityScopedFolderAccessError: Error, LocalizedError, Sendable {
    case missingBookmark
    case unresolvedBookmark(String)

    var errorDescription: String? {
        switch self {
        case .missingBookmark:
            return AppStrings.Errors.noSavedFolderAccess
        case .unresolvedBookmark(let reason):
            return AppStrings.Errors.savedFolderAccessCouldNotBeRestored(reason)
        }
    }
}

final class SecurityScopedFolderAccess: @unchecked Sendable {
    private let defaults: UserDefaults
    private let bookmarkKey: String

    init(defaults: UserDefaults = .standard, bookmarkKey: String = "stardewFolderBookmarkData") {
        self.defaults = defaults
        self.bookmarkKey = bookmarkKey
    }

    var hasBookmark: Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: bookmarkKey)
    }

    func clearBookmark() {
        defaults.removeObject(forKey: bookmarkKey)
    }

    func withAccess<T>(_ operation: () throws -> T) throws -> T {
        let token = try beginAccess()
        defer {
            token.stop()
        }

        return try operation()
    }

    func resolveBookmarkURL() throws -> URL? {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            return nil
        }

        return try resolveBookmarkURL(from: bookmarkData)
    }

    func beginAccess() throws -> SecurityScopedAccessToken {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            throw SecurityScopedFolderAccessError.missingBookmark
        }

        return try SecurityScopedAccessToken(url: resolveBookmarkURL(from: bookmarkData))
    }

    private func resolveBookmarkURL(from bookmarkData: Data) throws -> URL {
        var isStale = false

        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw SecurityScopedFolderAccessError.unresolvedBookmark(error.localizedDescription)
        }

        if isStale {
            // Creating a security-scoped bookmark requires active access to the
            // resource. Refreshing the stale bookmark is best effort: the
            // resolved URL still works for this launch even if the save fails.
            let token = SecurityScopedAccessToken(url: url)
            do {
                try saveBookmark(for: url)
                AppLog.folderAccess.info("Refreshed a stale bookmark (key: \(self.bookmarkKey, privacy: .public)).")
            } catch {
                AppLog.folderAccess.error("Couldn't refresh a stale bookmark (key: \(self.bookmarkKey, privacy: .public)): \(error)")
            }
            token.stop()
        }

        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

/// Shared bookkeeping for reporting lost folder access: clears the broken
/// bookmark and de-duplicates repeated failure messages so the same problem
/// isn't re-announced on every operation. Each owner uses its instance from a
/// single isolation context.
final class FolderAccessFailureReporter: @unchecked Sendable {
    private let folderAccess: SecurityScopedFolderAccess
    private var lastReportedMessage: String?

    init(folderAccess: SecurityScopedFolderAccess) {
        self.folderAccess = folderAccess
    }

    func noteSuccess() {
        lastReportedMessage = nil
    }

    /// Returns the user-facing message, or nil when this exact failure was
    /// already reported.
    func reportLostAccess(_ error: SecurityScopedFolderAccessError) -> String? {
        AppLog.folderAccess.error("Folder access lost; bookmark cleared: \(error)")
        folderAccess.clearBookmark()
        return deduplicated(AppStrings.Status.chooseModsFolderAgain(error.localizedDescription))
    }

    func reportRestoreFailure(_ error: Error) -> String? {
        AppLog.folderAccess.error("Folder access operation failed: \(error)")
        return deduplicated(AppStrings.Status.couldNotRestoreSavedFolderAccess(error.localizedDescription))
    }

    private func deduplicated(_ message: String) -> String? {
        guard lastReportedMessage != message else {
            return nil
        }

        lastReportedMessage = message
        return message
    }
}

final class SecurityScopedAccessToken {
    private let url: URL
    private let didStart: Bool
    private var isStopped = false

    init(url: URL) {
        self.url = url
        didStart = url.startAccessingSecurityScopedResource()
    }

    func stop() {
        guard !isStopped else {
            return
        }

        if didStart {
            url.stopAccessingSecurityScopedResource()
        }
        isStopped = true
    }

    deinit {
        stop()
    }
}
