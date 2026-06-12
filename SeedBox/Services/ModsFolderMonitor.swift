import CoreServices
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

/// Watches the Mods folder with FSEvents, which observes the whole tree —
/// including files edited in place inside mod folders — and coalesces bursts
/// of activity through its built-in latency.
final class ModsFolderMonitor: ModsFolderMonitoring, @unchecked Sendable {
    var onChange: (@MainActor () -> Void)?

    private let eventLatency: CFTimeInterval = 0.6
    private var stream: FSEventStreamRef?
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

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let nextStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else {
                    return
                }

                Unmanaged<ModsFolderMonitor>.fromOpaque(info)
                    .takeUnretainedValue()
                    .notifyChange()
            },
            &context,
            [standardizedURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            eventLatency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
        )

        guard let nextStream else {
            securityScopedAccess.stop()
            AppLog.monitor.error("FSEventStreamCreate failed for the Mods folder.")
            throw ModsFolderMonitorError.couldNotOpen(
                standardizedURL,
                "FSEventStreamCreate"
            )
        }

        FSEventStreamSetDispatchQueue(nextStream, .main)
        guard FSEventStreamStart(nextStream) else {
            FSEventStreamInvalidate(nextStream)
            FSEventStreamRelease(nextStream)
            securityScopedAccess.stop()
            AppLog.monitor.error("FSEventStreamStart failed for the Mods folder.")
            throw ModsFolderMonitorError.couldNotOpen(
                standardizedURL,
                "FSEventStreamStart"
            )
        }

        stream = nextStream
        watchedURL = standardizedURL
        self.securityScopedAccess = securityScopedAccess
        AppLog.monitor.info("Watching the Mods folder for changes.")
    }

    func stopWatching() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            AppLog.monitor.info("Stopped watching the Mods folder.")
        }
        stream = nil
        watchedURL = nil
        securityScopedAccess = nil
    }

    private func notifyChange() {
        AppLog.monitor.debug("FSEvents reported a change in the watched tree.")
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }

    deinit {
        stopWatching()
    }
}
