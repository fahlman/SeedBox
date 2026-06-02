import XCTest
@testable import SeedBox

final class ModLibraryTests: SeedBoxTestCase {
    func testScansEnabledAndDisabledMods() throws {
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

    func testDecodesContentPackAndDependencies() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let modURL = install.modDirectoryURL.appendingPathComponent("ExamplePack")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Example Pack",
            to: modURL,
            contentPackForUniqueID: "Pathoschild.ContentPatcher",
            dependencies: [
                ("AnotherMod.UniqueID", true),
                ("Optional.Mod", false)
            ]
        )

        let mod = try XCTUnwrap(
            ModLibrary.scan(install: install).first(where: { $0.folderName == "ExamplePack" })
        )
        let manifest = try XCTUnwrap(mod.manifest)

        XCTAssertEqual(manifest.contentPackFor?.uniqueID, "Pathoschild.ContentPatcher")
        XCTAssertEqual(manifest.dependencies?.count, 2)
        XCTAssertEqual(manifest.dependencies?.first?.uniqueID, "AnotherMod.UniqueID")
        XCTAssertEqual(manifest.dependencies?.first?.isRequired, true)
        XCTAssertEqual(mod.typeText, "Content Patcher")
        XCTAssertEqual(mod.manifestMetadataText, "For Pathoschild.ContentPatcher • 1 required + 1 optional deps")
    }

    func testClassifiesManifestModsAsSMAPI() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let modURL = install.modDirectoryURL.appendingPathComponent("SaveBackup")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Save Backup", to: modURL)

        let mod = try XCTUnwrap(
            ModLibrary.scan(install: install).first(where: { $0.folderName == "SaveBackup" })
        )

        XCTAssertEqual(mod.typeText, "SMAPI")
    }

    func testTreatsDependenciesWithoutIsRequiredAsRequired() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let modURL = install.modDirectoryURL.appendingPathComponent("PackWithDefaultRequiredDependency")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Pack With Default Required Dependency",
            to: modURL,
            uniqueID: "Author.PackWithDefaultRequiredDependency",
            dependencies: [
                ("Framework.RequiredByDefault", nil),
                ("Framework.Optional", false)
            ]
        )

        let mod = try XCTUnwrap(
            ModLibrary.scan(install: install).first {
                $0.folderName == "PackWithDefaultRequiredDependency"
            }
        )

        XCTAssertEqual(mod.manifestMetadataText, "1 required + 1 optional deps")
        XCTAssertEqual(mod.missingRequiredDependencyIDs, ["Framework.RequiredByDefault"])
        XCTAssertEqual(mod.missingOptionalDependencyIDs, ["Framework.Optional"])
    }

    func testFlagsMissingRequiredDependencies() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let modURL = install.modDirectoryURL.appendingPathComponent("PackA")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Pack A",
            to: modURL,
            uniqueID: "Author.PackA",
            dependencies: [
                ("Framework.Required", true),
                ("Framework.Optional", false)
            ]
        )

        let mod = try XCTUnwrap(
            ModLibrary.scan(install: install).first(where: { $0.folderName == "PackA" })
        )

        XCTAssertEqual(mod.missingRequiredDependencyIDs, ["Framework.Required"])
        XCTAssertEqual(mod.missingRequiredDependenciesText, "Missing required: Framework.Required")
        XCTAssertEqual(mod.missingOptionalDependencyIDs, ["Framework.Optional"])
        XCTAssertEqual(mod.missingOptionalDependenciesText, "Missing optional: Framework.Optional")
    }

    func testFlagsMissingOptionalDependencies() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let modURL = install.modDirectoryURL.appendingPathComponent("PackOptional")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Pack Optional",
            to: modURL,
            uniqueID: "Author.PackOptional",
            dependencies: [("Framework.OptionalOnly", false)]
        )

        let mod = try XCTUnwrap(
            ModLibrary.scan(install: install).first(where: { $0.folderName == "PackOptional" })
        )

        XCTAssertFalse(mod.hasMissingRequiredDependencies)
        XCTAssertEqual(mod.missingOptionalDependencyIDs, ["Framework.OptionalOnly"])
    }

    func testTreatsDisabledRequiredDependencyAsMissing() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let modURL = install.modDirectoryURL.appendingPathComponent("PackB")
        let disabledDependencyURL = install.modDirectoryURL.appendingPathComponent(".FrameworkRequired")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: disabledDependencyURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Pack B",
            to: modURL,
            uniqueID: "Author.PackB",
            dependencies: [("Framework.Required", true)]
        )
        try writeManifest(
            name: "Framework Required",
            to: disabledDependencyURL,
            uniqueID: "Framework.Required"
        )

        let mod = try XCTUnwrap(
            ModLibrary.scan(install: install).first(where: { $0.folderName == "PackB" })
        )

        XCTAssertEqual(mod.missingRequiredDependencyIDs, ["Framework.Required"])
    }

    func testClearsMissingRequiredDependenciesWhenEnabledDependencyExists() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let modURL = install.modDirectoryURL.appendingPathComponent("PackC")
        let dependencyURL = install.modDirectoryURL.appendingPathComponent("FrameworkRequired")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dependencyURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Pack C",
            to: modURL,
            uniqueID: "Author.PackC",
            dependencies: [("Framework.Required", true)]
        )
        try writeManifest(
            name: "Framework Required",
            to: dependencyURL,
            uniqueID: "Framework.Required"
        )

        let mod = try XCTUnwrap(
            ModLibrary.scan(install: install).first(where: { $0.folderName == "PackC" })
        )

        XCTAssertFalse(mod.hasMissingRequiredDependencies)
        XCTAssertEqual(mod.missingRequiredDependencyIDs, [])
    }

    func testClearsMissingOptionalDependenciesWhenEnabledOptionalExists() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let modURL = install.modDirectoryURL.appendingPathComponent("PackD")
        let dependencyURL = install.modDirectoryURL.appendingPathComponent("FrameworkOptional")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dependencyURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Pack D",
            to: modURL,
            uniqueID: "Author.PackD",
            dependencies: [("Framework.Optional", false)]
        )
        try writeManifest(
            name: "Framework Optional",
            to: dependencyURL,
            uniqueID: "Framework.Optional"
        )

        let mod = try XCTUnwrap(
            ModLibrary.scan(install: install).first(where: { $0.folderName == "PackD" })
        )

        XCTAssertFalse(mod.hasMissingOptionalDependencies)
        XCTAssertEqual(mod.missingOptionalDependencyIDs, [])
    }

    func testDisablesAndEnablesWithDotPrefix() throws {
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

    func testEnableRejectsExistingEnabledCopy() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let enabledURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let disabledURL = install.modDirectoryURL.appendingPathComponent(".ContentPatcher")

        try FileManager.default.createDirectory(at: enabledURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: disabledURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: enabledURL)
        try writeManifest(name: "Content Patcher", to: disabledURL)

        let disabledMod = try XCTUnwrap(
            ModLibrary.scan(install: install).first { !$0.isEnabled }
        )

        XCTAssertThrowsError(
            try ModLibrary.setEnabled(disabledMod, enabled: true)
        ) { error in
            guard case .modAlreadyInstalled(let folderName, let url) = error as? ModLibraryError else {
                XCTFail("Expected modAlreadyInstalled error, got \(error).")
                return
            }

            XCTAssertEqual(folderName, "ContentPatcher")
            assertSameFileURL(url, enabledURL)
        }
    }

    func testInstallsSelectedModFolder() throws {
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

    func testInstallsNestedManifestFolderInsteadOfWrapperFolder() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let downloadsURL = temporaryDirectory.appendingPathComponent("Downloads")
        let packageURL = downloadsURL.appendingPathComponent("Mod Download")
        let wrapperURL = packageURL.appendingPathComponent("Wrapper Folder")
        let modURL = wrapperURL.appendingPathComponent("ActualMod")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Actual Mod", to: modURL)
        try "Ignore me".write(
            to: packageURL.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        let installedURLs = try ModLibrary.installMods(from: [packageURL], into: install)

        XCTAssertEqual(installedURLs.map(\.lastPathComponent), ["ActualMod"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent("ActualMod")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL.appendingPathComponent("Wrapper Folder").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL.appendingPathComponent("README.txt").path
            )
        )
    }

    func testInstallsWrappedModFolderFromZipArchive() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let downloadsURL = temporaryDirectory.appendingPathComponent("Downloads")
        let packageURL = downloadsURL.appendingPathComponent("Archive Contents")
        let modURL = packageURL
            .appendingPathComponent("Outer Wrapper")
            .appendingPathComponent("ActualMod")
        let zipURL = downloadsURL.appendingPathComponent("ModDownload.zip")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Actual Mod", to: modURL)
        try "Ignore me".write(
            to: packageURL.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )
        try makeZip(from: packageURL, to: zipURL)

        let installedURLs = try ModLibrary.installMods(from: [zipURL], into: install)

        XCTAssertEqual(installedURLs.map(\.lastPathComponent), ["ActualMod"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent("ActualMod")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL.appendingPathComponent("Outer Wrapper").path
            )
        )
    }

    func testInstallsZipWithManifestAtArchiveRootUsingZipFileName() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let downloadsURL = temporaryDirectory.appendingPathComponent("Downloads")
        let packageURL = downloadsURL.appendingPathComponent("Archive Contents")
        let zipURL = downloadsURL.appendingPathComponent("RootPackedMod.zip")

        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try writeManifest(name: "Root Packed Mod", to: packageURL)
        try makeZip(from: packageURL, to: zipURL)

        let installedURLs = try ModLibrary.installMods(from: [zipURL], into: install)

        XCTAssertEqual(installedURLs.map(\.lastPathComponent), ["RootPackedMod"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL
                    .appendingPathComponent("RootPackedMod")
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )
    }

    func testInstallRejectsExistingDisabledCopy() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let downloadsURL = temporaryDirectory.appendingPathComponent("Downloads")
        let sourceURL = downloadsURL.appendingPathComponent("ContentPatcher")
        let existingDisabledURL = install.modDirectoryURL.appendingPathComponent(".ContentPatcher")

        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingDisabledURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: sourceURL)
        try writeManifest(name: "Content Patcher", to: existingDisabledURL)

        XCTAssertThrowsError(
            try ModLibrary.installMods(from: [sourceURL], into: install)
        ) { error in
            guard case .modAlreadyInstalled(let folderName, let url) = error as? ModLibraryError else {
                XCTFail("Expected modAlreadyInstalled error, got \(error).")
                return
            }

            XCTAssertEqual(folderName, "ContentPatcher")
            assertSameFileURL(url, existingDisabledURL)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL.appendingPathComponent("ContentPatcher").path
            )
        )
    }

    func testInstallRejectsEnabledAndDisabledCopiesInSameBatchBeforeCopying() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let downloadsURL = temporaryDirectory.appendingPathComponent("Downloads")
        let enabledSourceURL = downloadsURL.appendingPathComponent("ContentPatcher")
        let disabledSourceURL = downloadsURL.appendingPathComponent(".ContentPatcher")

        try FileManager.default.createDirectory(at: enabledSourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: disabledSourceURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: enabledSourceURL)
        try writeManifest(name: "Content Patcher", to: disabledSourceURL)

        XCTAssertThrowsError(
            try ModLibrary.installMods(from: [enabledSourceURL, disabledSourceURL], into: install)
        ) { error in
            XCTAssertEqual(
                error as? ModLibraryError,
                .modAlreadyInstalled(
                    "ContentPatcher",
                    install.modDirectoryURL.appendingPathComponent("ContentPatcher")
                )
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL.appendingPathComponent("ContentPatcher").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL.appendingPathComponent(".ContentPatcher").path
            )
        )
    }

    func testInstallPreflightsDestinationsBeforeCopying() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let downloadsURL = temporaryDirectory.appendingPathComponent("Downloads")
        let newModURL = downloadsURL.appendingPathComponent("NewMod")
        let conflictingModURL = downloadsURL.appendingPathComponent("ContentPatcher")
        let existingModURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: newModURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conflictingModURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingModURL, withIntermediateDirectories: true)
        try writeManifest(name: "New Mod", to: newModURL)
        try writeManifest(name: "Content Patcher", to: conflictingModURL)
        try writeManifest(name: "Content Patcher", to: existingModURL)

        XCTAssertThrowsError(
            try ModLibrary.installMods(from: [newModURL, conflictingModURL], into: install)
        ) { error in
            guard case .destinationExists(let destinationURL) = error as? ModLibraryError else {
                XCTFail("Expected destinationExists error, got \(error).")
                return
            }

            XCTAssertEqual(destinationURL.standardizedFileURL.path, existingModURL.standardizedFileURL.path)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: install.modDirectoryURL.appendingPathComponent("NewMod").path
            )
        )
    }

    private func makeZip(from sourceURL: URL, to zipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            sourceURL.path,
            zipURL.path
        ]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "SeedBoxTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "ditto failed to create \(zipURL.path)."
                ]
            )
        }
    }
}
