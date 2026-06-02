import XCTest
@testable import SeedBox

final class StardewInstallTests: SeedBoxTestCase {
    func testDefaultSteamPathUsesModsDirectoryInsideStardewBundle() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        XCTAssertEqual(
            StardewInstall.defaultModsDirectory(homeDirectory: home).path,
            "/Users/example/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods"
        )
    }

    func testDefaultModSetDirectoryUsesApplicationSupport() {
        let applicationSupportDirectory = URL(
            fileURLWithPath: "/Users/example/Library/Application Support",
            isDirectory: true
        )

        XCTAssertEqual(
            StardewInstall.defaultModSetDirectory(
                applicationSupportDirectory: applicationSupportDirectory
            )
            .path,
            "/Users/example/Library/Application Support/Seed Box/Mod Sets"
        )
    }

    func testDefaultAuditLogUsesApplicationSupport() {
        let applicationSupportDirectory = URL(
            fileURLWithPath: "/Users/example/Library/Application Support",
            isDirectory: true
        )

        XCTAssertEqual(
            StardewInstall.defaultAuditLogURL(
                applicationSupportDirectory: applicationSupportDirectory
            )
            .path,
            "/Users/example/Library/Application Support/Seed Box/Audit Log.plist"
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
            gogMacOSDirectory.appendingPathComponent("Mods").path
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
}
