import XCTest
@testable import SeedBox

final class ModSetStoreTests: SeedBoxTestCase {
    func testCreatesAndPersistsIncludedSets() throws {
        let install = try makeInstall()
        let consoleCommandsURL = install.modDirectoryURL.appendingPathComponent("ConsoleCommands")
        let contentPatcherURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")
        let saveBackupURL = install.modDirectoryURL.appendingPathComponent(".SaveBackup")

        try FileManager.default.createDirectory(at: consoleCommandsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contentPatcherURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: saveBackupURL, withIntermediateDirectories: true)
        try writeManifest(
            name: "Console Commands",
            to: consoleCommandsURL,
            uniqueID: "SMAPI.ConsoleCommands"
        )
        try writeManifest(name: "Content Patcher", to: contentPatcherURL)
        try writeManifest(
            name: "Save Backup",
            to: saveBackupURL,
            uniqueID: "SMAPI.SaveBackup"
        )

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)

        XCTAssertEqual(sets.prefix(4).map(\.name), [
            ModSetStore.allSetName,
            ModSetStore.defaultSetName,
            ModSetStore.noneSetName,
            ModSetStore.initialSetName
        ])

        let allSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.allSetID })
        XCTAssertTrue(allSet.isIncluded)
        XCTAssertFalse(allSet.isUserEditable)
        XCTAssertEqual(allSet.disabledFolderNames, [])

        let defaultSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.defaultSetID })
        XCTAssertTrue(defaultSet.isIncluded)
        XCTAssertFalse(defaultSet.isUserEditable)
        XCTAssertFalse(defaultSet.isUserRenamable)
        XCTAssertFalse(defaultSet.isUserDeletable)
        XCTAssertEqual(defaultSet.name, ModSetStore.defaultSetName)
        XCTAssertEqual(defaultSet.disabledFolderNames, ["ContentPatcher"])

        let noneSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.noneSetID })
        XCTAssertTrue(noneSet.isIncluded)
        XCTAssertFalse(noneSet.isUserEditable)
        XCTAssertEqual(noneSet.disabledFolderNames, ["ConsoleCommands", "ContentPatcher", "SaveBackup"])

        let initialSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.initialSetID })
        XCTAssertFalse(initialSet.isIncluded)
        XCTAssertTrue(initialSet.isUserEditable)
        XCTAssertTrue(initialSet.isUserRenamable)
        XCTAssertTrue(initialSet.isUserDeletable)
        XCTAssertEqual(initialSet.name, ModSetStore.initialSetName)
        XCTAssertEqual(initialSet.disabledFolderNames, ["SaveBackup"])

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

    func testDefaultIncludedSetUsesSMAPIBundledModsOnly() throws {
        let install = try makeInstall()
        try makeInstalledMod(
            name: "Console Commands",
            in: install,
            folderName: "ConsoleCommands",
            enabled: false,
            uniqueID: "SMAPI.ConsoleCommands"
        )
        try makeInstalledMod(
            name: "Save Backup",
            in: install,
            folderName: "SaveBackup",
            enabled: false,
            uniqueID: "SMAPI.SaveBackup"
        )
        try makeInstalledMod(
            name: "Content Patcher",
            in: install,
            folderName: "ContentPatcher"
        )

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)

        let defaultSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.defaultSetID })
        XCTAssertEqual(defaultSet.disabledFolderNames, ["ContentPatcher"])
    }

    func testDefaultIncludedSetRequiresSMAPIUniqueIDs() throws {
        let install = try makeInstall()
        try makeInstalledMod(
            name: "Console Commands",
            in: install,
            folderName: "ConsoleCommands"
        )
        try makeInstalledMod(
            name: "Save Backup",
            in: install,
            folderName: "SaveBackup"
        )

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)

        let defaultSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.defaultSetID })
        XCTAssertEqual(defaultSet.disabledFolderNames, ["ConsoleCommands", "SaveBackup"])
    }

    func testInitialSetCapturesFirstObservedModState() throws {
        let install = try makeInstall()
        try makeInstalledMod(
            name: "Console Commands",
            in: install,
            folderName: "ConsoleCommands",
            enabled: false
        )
        try makeInstalledMod(
            name: "Save Backup",
            in: install,
            folderName: "SaveBackup",
            enabled: false
        )
        try makeInstalledMod(
            name: "Content Patcher",
            in: install,
            folderName: "ContentPatcher"
        )

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)

        let initialSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.initialSetID })
        XCTAssertEqual(initialSet.name, ModSetStore.initialSetName)
        XCTAssertEqual(initialSet.disabledFolderNames, ["ConsoleCommands", "SaveBackup"])
    }

    func testLoadsStoredInitialSetWithoutChangingNameOrContents() throws {
        let install = try makeInstall()
        try makeInstalledMod(
            name: "Console Commands",
            in: install,
            folderName: "ConsoleCommands",
            uniqueID: "SMAPI.ConsoleCommands"
        )
        try makeInstalledMod(
            name: "Save Backup",
            in: install,
            folderName: "SaveBackup",
            uniqueID: "SMAPI.SaveBackup"
        )
        try makeInstalledMod(
            name: "Content Patcher",
            in: install,
            folderName: "ContentPatcher"
        )
        try writeStoredModSet(
            name: "Default",
            disabledFolderNames: ["SaveBackup"],
            install: install
        )

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)

        let initialSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.initialSetID })
        XCTAssertEqual(initialSet.name, "Default")
        XCTAssertEqual(initialSet.disabledFolderNames, ["SaveBackup"])
    }

    func testPreservesSavedMyModsContents() throws {
        let install = try makeInstall()
        try makeInstalledMod(
            name: "Console Commands",
            in: install,
            folderName: "ConsoleCommands",
            uniqueID: "SMAPI.ConsoleCommands"
        )
        try makeInstalledMod(
            name: "Save Backup",
            in: install,
            folderName: "SaveBackup",
            uniqueID: "SMAPI.SaveBackup"
        )
        try makeInstalledMod(
            name: "Content Patcher",
            in: install,
            folderName: "ContentPatcher"
        )
        try writeStoredModSet(
            name: ModSetStore.initialSetName,
            disabledFolderNames: ["SaveBackup"],
            install: install
        )

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)

        let initialSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.initialSetID })
        XCTAssertEqual(initialSet.name, ModSetStore.initialSetName)
        XCTAssertEqual(initialSet.disabledFolderNames, ["SaveBackup"])
    }

    func testDoesNotRecreateInitialSetAfterUserDeletesIt() throws {
        let install = try makeInstall()
        try makeInstalledMod(
            name: "Content Patcher",
            in: install,
            folderName: "ContentPatcher"
        )

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let initialSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.initialSetID })

        try ModSetStore.deleteSet(initialSet, install: install)

        let reloadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        XCTAssertFalse(reloadedSets.contains { $0.id == ModSetStore.initialSetID })
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
        let initialSet = try XCTUnwrap(loadedSets.first { $0.id == ModSetStore.initialSetID })
        let userSet = try ModSetStore.createSet(
            named: "Stardew Valley Expanded",
            from: initialSet,
            existingSets: loadedSets
        )

        try ModSetStore.saveSet(userSet, install: install)

        let reloadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let savedSet = try XCTUnwrap(reloadedSets.first(where: { $0.id == userSet.id }))
        XCTAssertEqual(savedSet.name, "Stardew Valley Expanded")
        XCTAssertFalse(savedSet.isIncluded)
        XCTAssertTrue(savedSet.isUserEditable)
    }

    func testSavesMyModsSetContents() throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let mods = try ModLibrary.scan(install: install)
        let loadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        var initialSet = try XCTUnwrap(loadedSets.first { $0.id == ModSetStore.initialSetID })
        initialSet.disabledFolderNames = ["ContentPatcher"]

        try ModSetStore.saveSet(initialSet, install: install)

        let reloadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let savedInitialSet = try XCTUnwrap(reloadedSets.first { $0.id == ModSetStore.initialSetID })
        XCTAssertEqual(savedInitialSet.id, ModSetStore.initialSetID)
        XCTAssertEqual(savedInitialSet.name, ModSetStore.initialSetName)
        XCTAssertEqual(savedInitialSet.disabledFolderNames, ["ContentPatcher"])
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

    func testDeletesMyModsSetLikeAnyUserSet() throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let myModsSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.initialSetID })

        try ModSetStore.deleteSet(myModsSet, install: install)

        let reloadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        XCTAssertFalse(reloadedSets.contains { $0.id == ModSetStore.initialSetID })
    }

    func testRejectsDuplicateSetNamesCaseInsensitive() throws {
        let baseSet = ModSet(
            id: ModSetStore.initialSetID,
            name: ModSetStore.initialSetName,
            disabledFolderNames: [],
            isIncluded: false
        )
        let existing = [
            baseSet,
            ModSet(
                id: UUID().uuidString,
                name: "Stardew Valley Expanded",
                disabledFolderNames: []
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

    func testRejectsUserSetNamedDefault() throws {
        let install = try makeInstall()
        try makeInstalledMod(name: "Content Patcher", in: install)

        let mods = try ModLibrary.scan(install: install)
        let loadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let initialSet = try XCTUnwrap(loadedSets.first { $0.id == ModSetStore.initialSetID })

        XCTAssertThrowsError(
            try ModSetStore.createSet(
                named: "default",
                from: initialSet,
                existingSets: loadedSets
            )
        ) { error in
            XCTAssertEqual(error as? ModSetStoreError, .duplicateSetName("default"))
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
            disabledFolderNames: ["ContentPatcher"]
        )

        _ = try ModSetStore.applySet(setToApply, install: install)

        let modsAfterApply = try ModLibrary.scan(install: install)
        let statusByFolder = Dictionary(
            uniqueKeysWithValues: modsAfterApply.map { ($0.enabledFolderName, $0.isEnabled) }
        )
        XCTAssertEqual(statusByFolder["ContentPatcher"], false)
        XCTAssertEqual(statusByFolder["SaveBackup"], true)
    }

    private func writeStoredModSet(
        name: String,
        disabledFolderNames: [String],
        install: StardewInstall
    ) throws {
        try FileManager.default.createDirectory(
            at: install.modSetDirectoryURL,
            withIntermediateDirectories: true
        )
        let payload: [String: Any] = [
            "id": ModSetStore.initialSetID,
            "name": name,
            "disabledFolderNames": disabledFolderNames
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )
        try data.write(
            to: install.modSetDirectoryURL.appendingPathComponent("\(ModSetStore.initialSetID).plist"),
            options: .atomic
        )
    }
}
