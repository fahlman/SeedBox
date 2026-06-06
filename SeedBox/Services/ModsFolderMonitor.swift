import Darwin
import Foundation

protocol ModsFolderMonitoring: AnyObject {
    var onChange: (@MainActor () -> Void)? { get set }
    var watchedPath: String? { get }

    func startWatching(_ url: URL, securityScopedAccess: SecurityScopedAccessToken) throws
    func stopWatching()
}

enum ModsFolderMonitorError: Error, LocalizedError {
    case couldNotOpen(URL, String)

    var errorDescription: String? {
        switch self {
        case .couldNotOpen(let url, let reason):
            return AppStrings.Errors.couldNotWatch(url.path, reason: reason)
        }
    }
}

final class ModsFolderMonitor: ModsFolderMonitoring, @unchecked Sendable {
    var onChange: (@MainActor () -> Void)?

    private let debounceInterval: DispatchTimeInterval = .milliseconds(600)
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var securityScopedAccess: SecurityScopedAccessToken?
    private var watchedURL: URL?

    var watchedPath: String? {
        watchedURL?.path
    }

    func startWatching(_ url: URL, securityScopedAccess: SecurityScopedAccessToken) throws {
        let standardizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        if watchedURL == standardizedURL {
            securityScopedAccess.stop()
            return
        }

        stopWatching()

        let fileDescriptor = open(standardizedURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            securityScopedAccess.stop()
            throw ModsFolderMonitorError.couldNotOpen(
                standardizedURL,
                String(cString: strerror(errno))
            )
        }

        let nextSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )

        nextSource.setEventHandler { [weak self] in
            self?.scheduleDebouncedChange()
        }
        nextSource.setCancelHandler {
            close(fileDescriptor)
        }

        source = nextSource
        watchedURL = standardizedURL
        self.securityScopedAccess = securityScopedAccess
        nextSource.resume()
    }

    func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
        watchedURL = nil
        securityScopedAccess = nil
    }

    private func scheduleDebouncedChange() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.onChange?()
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    deinit {
        stopWatching()
    }
}
