import XCTest
@testable import SeedBox

@MainActor
final class ModsFolderMonitorTests: SeedBoxTestCase {
    func testReportsChangeForFileEditedInsideNestedModFolder() async throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        let nestedDirectory = watchedDirectory.appendingPathComponent("Mod", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)

        let monitor = ModsFolderMonitor()
        defer {
            monitor.stopWatching()
        }

        var changeCount = 0
        monitor.onChange = {
            changeCount += 1
        }
        try monitor.startWatching(
            watchedDirectory,
            securityScopedAccess: SecurityScopedAccessToken(url: watchedDirectory)
        )
        XCTAssertEqual(
            monitor.watchedPath,
            watchedDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        )

        try "edited in place".write(
            to: nestedDirectory.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )

        try await waitUntil(timeout: .seconds(5)) {
            changeCount > 0
        }
    }


    func testStopWatchingClearsWatchedPath() throws {
        let watchedDirectory = temporaryDirectory.appendingPathComponent("Watched", isDirectory: true)
        try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)

        let monitor = ModsFolderMonitor()
        try monitor.startWatching(
            watchedDirectory,
            securityScopedAccess: SecurityScopedAccessToken(url: watchedDirectory)
        )
        XCTAssertNotNil(monitor.watchedPath)

        monitor.stopWatching()

        XCTAssertNil(monitor.watchedPath)
    }
}
