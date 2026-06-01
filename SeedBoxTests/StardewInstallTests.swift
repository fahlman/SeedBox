import XCTest

final class StardewInstallTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testDefaultSteamPathUsesModsDirectoryInsideStardewBundle() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        XCTAssertEqual(
            StardewInstall.defaultModsDirectory(homeDirectory: home).path,
            "/Users/example/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods"
        )
    }

    func testDefaultPathFallsBackToGOGWhenSteamMacOSIsMissing() throws {
        let home = temporaryDirectory.appendingPathComponent("Home", isDirectory: true)
        let applicationsDirectory = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        let gogMacOSDirectory = applicationsDirectory
            .appendingPathComponent("Stardew Valley.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")

        try FileManager.default.createDirectory(
            at: gogMacOSDirectory,
            withIntermediateDirectories: true
        )

        let defaultPath = StardewInstall.defaultModsDirectory(
            homeDirectory: home,
            applicationsDirectory: applicationsDirectory
        )

        XCTAssertEqual(
            defaultPath.path,
            applicationsDirectory
                .appendingPathComponent("Stardew Valley.app")
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS")
                .appendingPathComponent("Mods")
                .path
        )
    }

    func testKnownDefaultModsDirectoryDetectionIsFalseWhenNeitherExists() {
        let home = temporaryDirectory.appendingPathComponent("Home", isDirectory: true)
        let applicationsDirectory = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)

        XCTAssertFalse(
            StardewInstall.hasAnyKnownDefaultModsDirectory(
                homeDirectory: home,
                applicationsDirectory: applicationsDirectory
            )
        )
    }

    func testKnownDefaultModsDirectoryDetectionFindsSteamMods() throws {
        let home = temporaryDirectory.appendingPathComponent("Home", isDirectory: true)
        let applicationsDirectory = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        let steamModsDirectory = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Steam")
            .appendingPathComponent("steamapps")
            .appendingPathComponent("common")
            .appendingPathComponent("Stardew Valley")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("Mods")

        try FileManager.default.createDirectory(
            at: steamModsDirectory,
            withIntermediateDirectories: true
        )

        XCTAssertTrue(
            StardewInstall.hasAnyKnownDefaultModsDirectory(
                homeDirectory: home,
                applicationsDirectory: applicationsDirectory
            )
        )
    }

    func testKnownDefaultModsDirectoryDetectionFindsGOGMods() throws {
        let home = temporaryDirectory.appendingPathComponent("Home", isDirectory: true)
        let applicationsDirectory = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        let gogModsDirectory = applicationsDirectory
            .appendingPathComponent("Stardew Valley.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("Mods")

        try FileManager.default.createDirectory(
            at: gogModsDirectory,
            withIntermediateDirectories: true
        )

        XCTAssertTrue(
            StardewInstall.hasAnyKnownDefaultModsDirectory(
                homeDirectory: home,
                applicationsDirectory: applicationsDirectory
            )
        )
    }

    func testDefaultPathPrefersSteamWhenBothSteamAndGOGExist() throws {
        let home = temporaryDirectory.appendingPathComponent("Home", isDirectory: true)
        let applicationsDirectory = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        let steamMacOSDirectory = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("Steam")
            .appendingPathComponent("steamapps")
            .appendingPathComponent("common")
            .appendingPathComponent("Stardew Valley")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
        let gogMacOSDirectory = applicationsDirectory
            .appendingPathComponent("Stardew Valley.app")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")

        try FileManager.default.createDirectory(
            at: steamMacOSDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: gogMacOSDirectory,
            withIntermediateDirectories: true
        )

        let defaultPath = StardewInstall.defaultModsDirectory(
            homeDirectory: home,
            applicationsDirectory: applicationsDirectory
        )

        XCTAssertEqual(
            defaultPath.path,
            steamMacOSDirectory.appendingPathComponent("Mods").path
        )
    }

    func testInstallStatusCanManageModsWhenModsFolderExists() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)

        XCTAssertTrue(install.status().canManageMods)
    }

    func testInstallUsesProvidedModsFolder() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)

        XCTAssertEqual(install.modDirectoryURL.lastPathComponent, "Mods")
        XCTAssertEqual(install.modDirectoryURL.standardizedFileURL.path, modsDirectory.standardizedFileURL.path)
    }

    func testModLibraryScansEnabledAndDisabledMods() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let enabledURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let disabledURL = install.modDirectoryURL.appendingPathComponent(".SaveBackup")

        try FileManager.default.createDirectory(at: enabledURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: disabledURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: enabledURL)
        try writeManifest(name: "Save Backup", to: disabledURL)

        let mods = try ModLibrary.scan(install: install)

        XCTAssertEqual(mods.map(\.displayName), ["Content Patcher", "Save Backup"])
        XCTAssertEqual(mods.map(\.isEnabled), [true, false])
    }

    func testModLibraryDisablesAndEnablesWithDotPrefix() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)

        let mod = try XCTUnwrap(ModLibrary.scan(install: install).first)
        let disabledURL = try ModLibrary.setEnabled(mod, enabled: false)

        XCTAssertEqual(disabledURL.lastPathComponent, ".ContentPatcher")

        let disabledMod = try XCTUnwrap(ModLibrary.scan(install: install).first)
        let enabledURL = try ModLibrary.setEnabled(disabledMod, enabled: true)

        XCTAssertEqual(enabledURL.lastPathComponent, "ContentPatcher")
    }

    func testModLibraryInstallsSelectedModFolder() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let downloadsURL = temporaryDirectory.appendingPathComponent("Downloads")
        let modURL = downloadsURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let installedURLs = try ModLibrary.installMods(from: [modURL], into: install)

        XCTAssertEqual(installedURLs.map(\.lastPathComponent), ["ContentPatcher"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent("ContentPatcher")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )
    }

    private func makeModsDirectory() throws -> URL {
        let modsDirectory = temporaryDirectory
            .appendingPathComponent("Stardew Valley")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("Mods")
        try FileManager.default.createDirectory(
            at: modsDirectory,
            withIntermediateDirectories: true
        )
        return modsDirectory
    }

    private func writeManifest(name: String, to directoryURL: URL) throws {
        let data = """
        {
          "Name": "\(name)",
          "Author": "Test Author",
          "Version": "1.2.3",
          "Description": "A test mod.",
          "UniqueID": "Test.\(name.replacingOccurrences(of: " ", with: ""))"
        }
        """.data(using: .utf8)!

        try data.write(to: directoryURL.appendingPathComponent("manifest.json"))
    }
}
