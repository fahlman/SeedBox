import XCTest
@testable import SeedBox

final class ModSetStoreTests: SeedBoxTestCase {
    func testCreatesAndPersistsStarterSets() throws {
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

        XCTAssertEqual(sets.map(\.name), [
            ModSetStore.allSetName,
            ModSetStore.defaultSetName,
            ModSetStore.initialSetName,
            ModSetStore.noneSetName
        ])

        let allSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.allSetID })
        XCTAssertFalse(allSet.isUserEditable)
        XCTAssertFalse(allSet.isUserRenamable)
        XCTAssertFalse(allSet.isUserDeletable)
        XCTAssertEqual(allSet.disabledFolderNames, [])

        let defaultSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.defaultSetID })
        XCTAssertFalse(defaultSet.isUserEditable)
        XCTAssertFalse(defaultSet.isUserRenamable)
        XCTAssertFalse(defaultSet.isUserDeletable)
        XCTAssertEqual(defaultSet.name, ModSetStore.defaultSetName)
        XCTAssertEqual(defaultSet.disabledFolderNames, ["ContentPatcher"])

        let noneSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.noneSetID })
        XCTAssertFalse(noneSet.isUserEditable)
        XCTAssertFalse(noneSet.isUserRenamable)
        XCTAssertFalse(noneSet.isUserDeletable)
        XCTAssertEqual(noneSet.disabledFolderNames, ["ConsoleCommands", "ContentPatcher", "SaveBackup"])

        let initialSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.initialSetID })
        XCTAssertTrue(initialSet.isUserEditable)
        XCTAssertTrue(initialSet.isUserRenamable)
        XCTAssertTrue(initialSet.isUserDeletable)
        XCTAssertEqual(initialSet.name, ModSetStore.initialSetName)
        XCTAssertEqual(initialSet.disabledFolderNames, ["SaveBackup"])

        let expectedEditabilityBySetID = [
            ModSetStore.allSetID: false,
            ModSetStore.defaultSetID: false,
            ModSetStore.initialSetID: true,
            ModSetStore.noneSetID: false
        ]
        for (setID, isEditable) in expectedEditabilityBySetID {
            let payload = try storedModSetPayload(id: setID, install: install)
            XCTAssertEqual(payload["isEditable"] as? Bool, isEditable)
        }
    }

    func testDefaultStarterSetUsesSMAPIBundledModsOnly() throws {
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

    func testDefaultStarterSetRequiresSMAPIUniqueIDs() throws {
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

    func testLoadsStoredMyModsSetWithoutChangingNameOrContents() throws {
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
            name: "My Saved Mods",
            disabledFolderNames: ["SaveBackup"],
            install: install
        )

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)

        let initialSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.initialSetID })
        XCTAssertEqual(initialSet.name, "My Saved Mods")
        XCTAssertTrue(initialSet.isUserEditable)
        XCTAssertEqual(initialSet.disabledFolderNames, ["SaveBackup"])
        let payload = try storedModSetPayload(id: ModSetStore.initialSetID, install: install)
        XCTAssertEqual(payload["isEditable"] as? Bool, true)
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

    func testPreservesStarterSetContentsWhenModsChange() throws {
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
        XCTAssertEqual(noneSet.disabledFolderNames, ["ContentPatcher"])
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
        XCTAssertTrue(savedSet.isUserEditable)
        let payload = try storedModSetPayload(id: savedSet.id, install: install)
        XCTAssertEqual(payload["isEditable"] as? Bool, true)
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
        XCTAssertTrue(savedInitialSet.isUserEditable)
        XCTAssertEqual(savedInitialSet.disabledFolderNames, ["ContentPatcher"])
    }

    func testMigratesStoredAppProvidedSetWithoutEditabilityFlag() throws {
        let install = try makeInstall()
        try writeStoredModSet(
            id: ModSetStore.allSetID,
            name: ModSetStore.allSetName,
            disabledFolderNames: [],
            install: install
        )

        let sets = try ModSetStore.loadSets(install: install, currentMods: [])

        let allSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.allSetID })
        XCTAssertFalse(allSet.isUserEditable)
        XCTAssertFalse(allSet.isUserRenamable)
        XCTAssertFalse(allSet.isUserDeletable)

        let payload = try storedModSetPayload(id: ModSetStore.allSetID, install: install)
        XCTAssertEqual(payload["isEditable"] as? Bool, false)
    }

    func testDeletesStarterSetLikeAnyUserSet() throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent("ContentPatcher")

        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)

        let mods = try ModLibrary.scan(install: install)
        let sets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let allSet = try XCTUnwrap(sets.first { $0.id == ModSetStore.allSetID })

        try ModSetStore.deleteSet(allSet, install: install)

        let reloadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        XCTAssertFalse(reloadedSets.contains { $0.id == ModSetStore.allSetID })
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
            disabledFolderNames: []
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
        id: String = ModSetStore.initialSetID,
        name: String,
        disabledFolderNames: [String],
        isEditable: Bool? = nil,
        install: StardewInstall
    ) throws {
        try FileManager.default.createDirectory(
            at: install.modSetDirectoryURL,
            withIntermediateDirectories: true
        )
        var payload: [String: Any] = [
            "id": id,
            "name": name,
            "disabledFolderNames": disabledFolderNames
        ]
        if let isEditable {
            payload["isEditable"] = isEditable
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )
        try data.write(
            to: install.modSetDirectoryURL.appendingPathComponent("\(id).plist"),
            options: .atomic
        )
    }

    private func storedModSetPayload(id: String, install: StardewInstall) throws -> [String: Any] {
        let url = install.modSetDirectoryURL.appendingPathComponent("\(id).plist")
        let data = try Data(contentsOf: url)
        let payload = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return try XCTUnwrap(payload)
    }
}
