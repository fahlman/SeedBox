import Foundation

@MainActor
final class ModManagerFolderObservation {
    private let folderAccess: SecurityScopedFolderAccess
    private let monitor: ModsFolderMonitoring
    private let notifier: ModFolderChangeNotifying
    private var ignoredChangeDeadline = Date.distantPast

    init(
        folderAccess: SecurityScopedFolderAccess,
        monitor: ModsFolderMonitoring,
        notifier: ModFolderChangeNotifying,
        onChange: @escaping @MainActor () async -> Void
    ) {
        self.folderAccess = folderAccess
        self.monitor = monitor
        self.notifier = notifier
        self.monitor.onChange = {
            Task { @MainActor in
                await onChange()
            }
        }
    }

    func ignoreChangesBriefly() {
        ignoredChangeDeadline = Date().addingTimeInterval(2)
    }

    var shouldHandleObservedChange: Bool {
        Date() >= ignoredChangeDeadline
    }

    func notifyObservedChange() {
        notifier.notifyModsFolderChanged()
    }

    func synchronizeWatching(
        for state: ModManagerState,
        install: StardewInstall
    ) -> String? {
        guard state.readiness.canManageMods else {
            monitor.stopWatching()
            return nil
        }

        let modsDirectoryURL = install.modDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard monitor.watchedPath != modsDirectoryURL.path else {
            return nil
        }

        do {
            let accessToken = try folderAccess.beginAccess()
            try monitor.startWatching(
                modsDirectoryURL,
                securityScopedAccess: accessToken
            )
            return nil
        } catch {
            monitor.stopWatching()
            return AppStrings.Status.couldNotWatchModsFolder(error.localizedDescription)
        }
    }
}
