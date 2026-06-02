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

    func testModSetStoreCreatesAndPersistsDefaultSet() throws {
        let install = try makeInstall()
        let enabledURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let disabledURL = install.modDirectoryURL.appendingPathComponent(".SaveBackup")

        try FileManager.default.createDirectory(at: enabledURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: disabledURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: enabledURL)
        try writeManifest(name: "Save Backup", to: disabledURL)

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)

        let defaultSet = try XCTUnwrap(sets.first(where: \.isDefault))
        XCTAssertEqual(defaultSet.id, ModSetStore.defaultSetID)
        XCTAssertEqual(defaultSet.disabledFolderNames, ["SaveBackup"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: install.modSetDirectoryURL
                    .appendingPathComponent("\(ModSetStore.defaultSetID).plist")
                    .path
            )
        )
    }

    func testModSetStoreSavesAndLoadsUserSet() throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let mods = try ModLibrary.scan(install: install)
        let loadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let defaultSet = try XCTUnwrap(loadedSets.first(where: \.isDefault))
        let userSet = try ModSetStore.createSet(
            named: "Stardew Valley Expanded",
            from: defaultSet,
            existingSets: loadedSets
        )

        try ModSetStore.saveSet(userSet, install: install)

        let reloadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let savedSet = try XCTUnwrap(reloadedSets.first(where: { $0.id == userSet.id }))
        XCTAssertEqual(savedSet.name, "Stardew Valley Expanded")
        XCTAssertFalse(savedSet.isDefault)
    }

    func testModSetStoreRejectsDuplicateSetNamesCaseInsensitive() throws {
        let baseSet = ModSet(
            id: ModSetStore.defaultSetID,
            name: ModSetStore.defaultSetName,
            disabledFolderNames: [],
            isDefault: true
        )
        let existing = [
            baseSet,
            ModSet(
                id: UUID().uuidString,
                name: "Stardew Valley Expanded",
                disabledFolderNames: [],
                isDefault: false
            )
        ]

        XCTAssertThrowsError(
            try ModSetStore.createSet(
                named: "stardew valley expanded",
                from: baseSet,
                existingSets: existing
            )
        ) { error in
            XCTAssertEqual(error as? ModSetStoreError, .duplicateSetName("stardew valley expanded"))
        }
    }

    func testModSetStoreApplySetTogglesModsFromDisabledFolderList() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let enabledURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let disabledURL = install.modDirectoryURL.appendingPathComponent(".SaveBackup")

        try FileManager.default.createDirectory(at: enabledURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: disabledURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: enabledURL)
        try writeManifest(name: "Save Backup", to: disabledURL)

        let setToApply = ModSet(
            id: "test-set",
            name: "Test Set",
            disabledFolderNames: ["ContentPatcher"],
            isDefault: false
        )

        _ = try ModSetStore.applySet(setToApply, install: install)

        let modsAfterApply = try ModLibrary.scan(install: install)
        let statusByFolder = Dictionary(
            uniqueKeysWithValues: modsAfterApply.map { ($0.enabledFolderName, $0.isEnabled) }
        )
        XCTAssertEqual(statusByFolder["ContentPatcher"], false)
        XCTAssertEqual(statusByFolder["SaveBackup"], true)
    }

    func testModLibraryDecodesContentPackAndDependencies() throws {
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

    func testModLibraryClassifiesManifestModsAsSMAPI() throws {
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

    func testModSearchQueryMatchesColumnFilters() throws {
        let modsDirectory = try makeModsDirectory()
        let install = StardewInstall(modsDirectory: modsDirectory)
        let smapiURL = install.modDirectoryURL.appendingPathComponent("SaveBackup")
        let contentPackURL = install.modDirectoryURL.appendingPathComponent(".ExamplePack")

        try FileManager.default.createDirectory(at: smapiURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contentPackURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Save Backup",
            to: smapiURL,
            author: "ConcernedApe"
        )
        try writeManifest(
            name: "Example Pack",
            to: contentPackURL,
            author: "Pathoschild Games",
            contentPackForUniqueID: "Pathoschild.ContentPatcher"
        )

        let mods = try ModLibrary.scan(install: install)
        let enabledSMAPIMatches = mods.filter {
            ModSearchQuery("state:enabled type:smapi author:ConcernedApe").matches($0)
        }
        let disabledContentPackMatches = mods.filter {
            ModSearchQuery("state:disabled type:content-patcher mod:Example").matches($0)
        }
        let quotedAuthorMatches = mods.filter {
            ModSearchQuery("author:\"Pathoschild Games\"").matches($0)
        }

        XCTAssertEqual(enabledSMAPIMatches.map(\.displayName), ["Save Backup"])
        XCTAssertEqual(disabledContentPackMatches.map(\.displayName), ["Example Pack"])
        XCTAssertEqual(quotedAuthorMatches.map(\.displayName), ["Example Pack"])
    }

    func testModLibraryTreatsDependenciesWithoutIsRequiredAsRequired() throws {
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

    func testModLibraryFlagsMissingRequiredDependencies() throws {
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

    func testModLibraryFlagsMissingOptionalDependencies() throws {
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

    func testModLibraryTreatsDisabledRequiredDependencyAsMissing() throws {
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

    func testModLibraryClearsMissingRequiredDependenciesWhenEnabledDependencyExists() throws {
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

    func testModLibraryClearsMissingOptionalDependenciesWhenEnabledOptionalExists() throws {
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

    func testModLibraryEnableRejectsExistingEnabledCopy() throws {
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

    func testModLibraryInstallRejectsExistingDisabledCopy() throws {
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

    func testModLibraryInstallRejectsEnabledAndDisabledCopiesInSameBatchBeforeCopying() throws {
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

    func testModLibraryInstallPreflightsDestinationsBeforeCopying() throws {
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

    private func makeInstall() throws -> StardewInstall {
        let modsDirectory = try makeModsDirectory()
        let modSetDirectory = temporaryDirectory
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Seed Box", isDirectory: true)
            .appendingPathComponent("Mod Sets", isDirectory: true)

        return StardewInstall(
            modsDirectory: modsDirectory,
            modSetDirectory: modSetDirectory
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

    private func assertSameFileURL(
        _ actualURL: URL,
        _ expectedURL: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actualURL.standardizedFileURL.resolvingSymlinksInPath().path,
            expectedURL.standardizedFileURL.resolvingSymlinksInPath().path,
            file: file,
            line: line
        )
    }

    private func writeManifest(
        name: String,
        to directoryURL: URL,
        author: String = "Test Author",
        uniqueID: String? = nil,
        contentPackForUniqueID: String? = nil,
        dependencies: [(uniqueID: String, isRequired: Bool?)] = []
    ) throws {
        var manifest: [String: Any] = [
            "Name": name,
            "Author": author,
            "Version": "1.2.3",
            "Description": "A test mod.",
            "UniqueID": uniqueID ?? "Test.\(name.replacingOccurrences(of: " ", with: ""))"
        ]

        if let contentPackForUniqueID {
            manifest["ContentPackFor"] = [
                "UniqueID": contentPackForUniqueID
            ]
        }

        if !dependencies.isEmpty {
            manifest["Dependencies"] = dependencies.map { dependency in
                var encodedDependency: [String: Any] = [
                    "UniqueID": dependency.uniqueID
                ]

                if let isRequired = dependency.isRequired {
                    encodedDependency["IsRequired"] = isRequired
                }

                return encodedDependency
            }
        }

        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: directoryURL.appendingPathComponent("manifest.json"))
    }

}
