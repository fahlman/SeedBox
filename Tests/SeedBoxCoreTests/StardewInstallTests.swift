import XCTest
@testable import SeedBoxCore

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

    func testDefaultSteamPathUsesMacOSDirectoryInsideStardewBundle() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        XCTAssertEqual(
            StardewInstallLocator.defaultMacOSDirectory(homeDirectory: home).path,
            "/Users/example/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS"
        )
    }

    func testResolveMacOSDirectoryFromGameRoot() throws {
        let macOSDirectory = temporaryDirectory
            .appendingPathComponent("Stardew Valley")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(
            at: macOSDirectory,
            withIntermediateDirectories: true
        )

        let resolved = StardewInstallLocator.resolveMacOSDirectory(
            from: temporaryDirectory.appendingPathComponent("Stardew Valley")
        )

        XCTAssertEqual(resolved.path, macOSDirectory.standardizedFileURL.path)
    }

    func testInstallStatusIsLaunchableWhenSMAPIAndModsFolderExist() throws {
        let macOSDirectory = try makeMacOSDirectory()
        let install = StardewInstall(macOSDirectory: macOSDirectory)

        try makeExecutable(at: install.smapiExecutableURL)
        try FileManager.default.createDirectory(at: install.modDirectoryURL, withIntermediateDirectories: true)

        XCTAssertTrue(install.status().canLaunch)
    }

    func testLaunchRequestUsesFixedSVEModsPathArgument() throws {
        let macOSDirectory = try makeMacOSDirectory()
        let install = StardewInstall(macOSDirectory: macOSDirectory)

        try makeExecutable(at: install.smapiExecutableURL)
        try FileManager.default.createDirectory(at: install.modDirectoryURL, withIntermediateDirectories: true)

        let request = try SMAPILauncher.request(for: install)

        XCTAssertEqual(request.executableURL, install.smapiExecutableURL)
        XCTAssertEqual(request.currentDirectoryURL, install.macOSDirectory)
        XCTAssertEqual(request.arguments, ["--mods-path", "Mods-SVE"])
    }

    func testLinkVanillaModsCreatesSymlinksWithoutOverwritingExistingFiles() throws {
        let macOSDirectory = try makeMacOSDirectory()
        let install = StardewInstall(macOSDirectory: macOSDirectory)
        let contentPatcher = install.vanillaModDirectoryURL.appendingPathComponent("ContentPatcher")
        let existingMod = install.modDirectoryURL.appendingPathComponent("AlreadyHere")

        try FileManager.default.createDirectory(at: install.vanillaModDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contentPatcher, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: install.modDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingMod, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: install.vanillaModDirectoryURL.appendingPathComponent("AlreadyHere"),
            withIntermediateDirectories: true
        )

        let result = try ModFolderSeeder.linkVanillaMods(into: install)

        XCTAssertEqual(result.linkedCount, 1)
        XCTAssertEqual(result.skippedCount, 1)

        let linkedURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: linkedURL.path)
        XCTAssertEqual(
            URL(fileURLWithPath: destination).resolvingSymlinksInPath().path,
            contentPatcher.resolvingSymlinksInPath().path
        )
    }

    func testModLibraryScansEnabledAndDisabledMods() throws {
        let macOSDirectory = try makeMacOSDirectory()
        let install = StardewInstall(macOSDirectory: macOSDirectory)
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
        let macOSDirectory = try makeMacOSDirectory()
        let install = StardewInstall(macOSDirectory: macOSDirectory)
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
        let macOSDirectory = try makeMacOSDirectory()
        let install = StardewInstall(macOSDirectory: macOSDirectory)
        let downloadsURL = temporaryDirectory.appendingPathComponent("Downloads")
        let modURL = downloadsURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: install.modDirectoryURL, withIntermediateDirectories: true)
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

    private func makeMacOSDirectory() throws -> URL {
        let macOSDirectory = temporaryDirectory
            .appendingPathComponent("Stardew Valley")
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(
            at: macOSDirectory,
            withIntermediateDirectories: true
        )
        return macOSDirectory
    }

    private func makeExecutable(at url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
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
