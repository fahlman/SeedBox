import Foundation

final class SecurityScopedFolderAccess {
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
            token?.stop()
        }

        return try operation()
    }

    func beginAccess() throws -> SecurityScopedAccessToken? {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            try saveBookmark(for: url)
        }

        return SecurityScopedAccessToken(url: url)
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
