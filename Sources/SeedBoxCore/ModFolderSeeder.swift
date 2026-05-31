import Foundation

public enum ModFolderSeeder {
    public struct SeedResult: Equatable {
        public var createdModDirectory: Bool
        public var linkedCount: Int
        public var skippedCount: Int

        public var summary: String {
            var pieces: [String] = []
            if createdModDirectory {
                pieces.append("created \(StardewInstall.modFolderName)")
            }
            pieces.append("linked \(linkedCount)")
            pieces.append("skipped \(skippedCount)")
            return pieces.joined(separator: ", ")
        }
    }

    public static func linkVanillaMods(
        into install: StardewInstall,
        fileManager: FileManager = .default
    ) throws -> SeedResult {
        guard fileManager.directoryExists(at: install.vanillaModDirectoryURL) else {
            throw LauncherError.missingVanillaModDirectory(install.vanillaModDirectoryURL)
        }

        var createdModDirectory = false
        if !fileManager.directoryExists(at: install.modDirectoryURL) {
            try install.createModDirectory(fileManager: fileManager)
            createdModDirectory = true
        }

        let vanillaMods = try fileManager.contentsOfDirectory(
            at: install.vanillaModDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var linkedCount = 0
        var skippedCount = 0

        for sourceURL in vanillaMods {
            let destinationURL = install.modDirectoryURL
                .appendingPathComponent(sourceURL.lastPathComponent)

            if fileManager.fileExists(atPath: destinationURL.path) {
                skippedCount += 1
                continue
            }

            try fileManager.createSymbolicLink(
                at: destinationURL,
                withDestinationURL: sourceURL
            )
            linkedCount += 1
        }

        return SeedResult(
            createdModDirectory: createdModDirectory,
            linkedCount: linkedCount,
            skippedCount: skippedCount
        )
    }
}
