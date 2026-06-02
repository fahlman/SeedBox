import XCTest
@testable import SeedBox

final class ModSetStoreTests: SeedBoxTestCase {
    func testCreatesAndPersistsDefaultSet() throws {
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

    func testSavesAndLoadsUserSet() throws {
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

    func testSavesDefaultSetContents() throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let mods = try ModLibrary.scan(install: install)
        let loadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        var defaultSet = try XCTUnwrap(loadedSets.first(where: \.isDefault))
        defaultSet.disabledFolderNames = ["ContentPatcher"]

        try ModSetStore.saveSet(defaultSet, install: install)

        let reloadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let savedDefaultSet = try XCTUnwrap(reloadedSets.first(where: \.isDefault))
        XCTAssertEqual(savedDefaultSet.id, ModSetStore.defaultSetID)
        XCTAssertEqual(savedDefaultSet.name, ModSetStore.defaultSetName)
        XCTAssertEqual(savedDefaultSet.disabledFolderNames, ["ContentPatcher"])
    }

    func testRejectsDuplicateSetNamesCaseInsensitive() throws {
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

    func testApplySetTogglesModsFromDisabledFolderList() throws {
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
}
