import Foundation

public enum StardewInstallLocator {
    public static func defaultMacOSDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Steam")
            .appendingPathComponent("steamapps")
            .appendingPathComponent("common")
            .appendingPathComponent("Stardew Valley")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
    }

    public static func candidateMacOSDirectories(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            defaultMacOSDirectory(homeDirectory: homeDirectory),
            homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent("Steam")
                .appendingPathComponent("steamapps")
                .appendingPathComponent("common")
                .appendingPathComponent("Stardew Valley")
                .appendingPathComponent("Stardew Valley.app")
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS"),
            URL(fileURLWithPath: "/Applications")
                .appendingPathComponent("Stardew Valley.app")
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS")
        ]
    }

    public static func locateInstalledMacOSDirectory(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        candidateMacOSDirectories(homeDirectory: homeDirectory).first { candidate in
            looksLikeStardewMacOSDirectory(candidate, fileManager: fileManager)
        } ?? defaultMacOSDirectory(homeDirectory: homeDirectory)
    }

    public static func resolveMacOSDirectory(
        from selectedURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let selected = selectedURL.standardizedFileURL.resolvingSymlinksInPath()

        if selected.lastPathComponent == "MacOS",
           fileManager.directoryExists(at: selected) {
            return selected
        }

        let directBundleContents = selected
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
        if fileManager.directoryExists(at: directBundleContents) {
            return directBundleContents
        }

        let nestedAppContents = selected
            .appendingPathComponent("Stardew Valley.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
        if fileManager.directoryExists(at: nestedAppContents) {
            return nestedAppContents
        }

        return directBundleContents
    }

    public static func looksLikeStardewMacOSDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.directoryExists(at: url) else {
            return false
        }

        let knownExecutables = [
            "Stardew Valley",
            "StardewValley"
        ]

        return knownExecutables.contains { name in
            fileManager.fileExists(atPath: url.appendingPathComponent(name).path)
        }
    }
}
