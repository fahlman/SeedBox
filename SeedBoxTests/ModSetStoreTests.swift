import XCTest
@testable import SeedBox

final class ModSetStoreTests: SeedBoxTestCase {
    func testCreatesAndPersistsIncludedSets() throws {
        let install = try makeInstall()
        let enabledURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let disabledURL = install.modDirectoryURL.appendingPathComponent(".SaveBackup")

        try FileManager.default.createDirectory(at: enabledURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: disabledURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: enabledURL)
        try writeManifest(name: "Save Backup", to: disabledURL)

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)

        XCTAssertEqual(sets.prefix(3).map(\.name), [
            ModSetStore.allSetName,
            ModSetStore.noneSetName,
            ModSetStore.defaultSetName
        ])

        let allSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.allSetID })
        XCTAssertTrue(allSet.isIncluded)
        XCTAssertFalse(allSet.isUserEditable)
        XCTAssertEqual(allSet.disabledFolderNames, [])

        let noneSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.noneSetID })
        XCTAssertTrue(noneSet.isIncluded)
        XCTAssertFalse(noneSet.isUserEditable)
        XCTAssertEqual(noneSet.disabledFolderNames, ["ContentPatcher", "SaveBackup"])

        let defaultSet = try XCTUnwrap(sets.first(where: \.isDefault))
        XCTAssertTrue(defaultSet.isIncluded)
        XCTAssertFalse(defaultSet.isUserEditable)
        XCTAssertEqual(defaultSet.id, ModSetStore.defaultSetID)
        XCTAssertEqual(defaultSet.disabledFolderNames, ["SaveBackup"])

        for setID in ModSetStore.includedSetIDs {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: install.modSetDirectoryURL
                        .appendingPathComponent("\(setID).plist")
                        .path
                )
            )
        }
    }

    func testUpdatesNoneIncludedSetWhenModsChange() throws {
        let install = try makeInstall()
        let contentPatcherURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let saveBackupURL = install.modDirectoryURL.appendingPathComponent("SaveBackup")

        try FileManager.default.createDirectory(at: contentPatcherURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: contentPatcherURL)

        var mods = try ModLibrary.scan(install: install)
        var sets = try ModSetStore.loadSets(install: install, currentMods: mods)
        var allSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.allSetID })
        var noneSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.noneSetID })
        XCTAssertEqual(allSet.disabledFolderNames, [])
        XCTAssertEqual(noneSet.disabledFolderNames, ["ContentPatcher"])

        try FileManager.default.createDirectory(at: saveBackupURL, withIntermediateDirectories: true)
        try writeManifest(name: "Save Backup", to: saveBackupURL)

        mods = try ModLibrary.scan(install: install)
        sets = try ModSetStore.loadSets(install: install, currentMods: mods)
        allSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.allSetID })
        noneSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.noneSetID })
        XCTAssertEqual(allSet.disabledFolderNames, [])
        XCTAssertEqual(noneSet.disabledFolderNames, ["ContentPatcher", "SaveBackup"])
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
        XCTAssertFalse(savedSet.isIncluded)
        XCTAssertTrue(savedSet.isUserEditable)
    }

    func testRejectsSavingIncludedSetContents() throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let mods = try ModLibrary.scan(install: install)
        let loadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        var defaultSet = try XCTUnwrap(loadedSets.first(where: \.isDefault))
        defaultSet.disabledFolderNames = ["ContentPatcher"]

        XCTAssertThrowsError(try ModSetStore.saveSet(defaultSet, install: install)) { error in
            XCTAssertEqual(error as? ModSetStoreError, .cannotEditIncludedSet)
        }

        let reloadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let savedDefaultSet = try XCTUnwrap(reloadedSets.first(where: \.isDefault))
        XCTAssertEqual(savedDefaultSet.id, ModSetStore.defaultSetID)
        XCTAssertEqual(savedDefaultSet.name, ModSetStore.defaultSetName)
        XCTAssertEqual(savedDefaultSet.disabledFolderNames, [])
    }

    func testRejectsDeletingIncludedSets() throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)
        for includedSet in sets.filter(\.isIncluded) {
            XCTAssertThrowsError(try ModSetStore.deleteSet(includedSet, install: install)) { error in
                XCTAssertEqual(error as? ModSetStoreError, .cannotDeleteIncludedSet)
            }
        }
    }

    func testRejectsDuplicateSetNamesCaseInsensitive() throws {
        let baseSet = ModSet(
            id: ModSetStore.defaultSetID,
            name: ModSetStore.defaultSetName,
            disabledFolderNames: [],
            isDefault: true,
            isIncluded: true
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
