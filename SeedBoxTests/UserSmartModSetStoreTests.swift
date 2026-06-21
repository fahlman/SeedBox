import XCTest
@testable import SeedBox

@MainActor
final class UserSmartModSetStoreTests: SeedBoxTestCase {
    func testCreatesSmartModSetFromValidatedSearch() throws {
        let smartModSet = try UserSmartModSetStore.createSmartModSet(
            named: "  Updates  ",
            searchText: "  updates:available  ",
            existingSmartModSets: [],
            id: "  updates  "
        )

        XCTAssertEqual(smartModSet.id, "updates")
        XCTAssertEqual(smartModSet.name, "Updates")
        XCTAssertEqual(smartModSet.searchText, "updates:available")
        XCTAssertEqual(smartModSet.systemImageName, UserSmartModSet.defaultSystemImageName)
    }

    func testRejectsEmptyNamesAndSearchText() {
        XCTAssertThrowsError(
            try UserSmartModSetStore.createSmartModSet(
                named: "Updates",
                searchText: "updates:available",
                existingSmartModSets: [],
                id: " "
            )
        ) { error in
            XCTAssertEqual(error as? UserSmartModSetStoreError, .emptyID)
        }

        XCTAssertThrowsError(
            try UserSmartModSetStore.createSmartModSet(
                named: "  ",
                searchText: "updates:available",
                existingSmartModSets: []
            )
        ) { error in
            XCTAssertEqual(error as? UserSmartModSetStoreError, .emptyName)
        }

        XCTAssertThrowsError(
            try UserSmartModSetStore.createSmartModSet(
                named: "Updates",
                searchText: "  ",
                existingSmartModSets: []
            )
        ) { error in
            XCTAssertEqual(error as? UserSmartModSetStoreError, .emptySearchText)
        }
    }

    func testRejectsDuplicateNamesCaseInsensitive() {
        let existing = [
            UserSmartModSet(
                id: "updates",
                name: "Updates",
                searchText: "updates:available"
            )
        ]

        XCTAssertThrowsError(
            try UserSmartModSetStore.createSmartModSet(
                named: " updates ",
                searchText: "type:smapi",
                existingSmartModSets: existing
            )
        ) { error in
            XCTAssertEqual(error as? UserSmartModSetStoreError, .duplicateName("updates"))
        }
    }

    func testRejectsReservedNames() {
        XCTAssertThrowsError(
            try UserSmartModSetStore.createSmartModSet(
                named: "All Mods",
                searchText: "state:enabled",
                existingSmartModSets: [],
                reservedNames: ["All Mods"]
            )
        ) { error in
            XCTAssertEqual(error as? UserSmartModSetStoreError, .duplicateName("All Mods"))
        }
    }

    func testSavesAndLoadsSmartModSetsInApplicationSupport() throws {
        let install = try makeInstall()
        let storeURL = StardewInstall.smartModSetStoreURL(
            forModSetDirectory: install.modSetDirectoryURL
        )
        let laterAlphabetically = UserSmartModSet(
            id: "smapi",
            name: "SMAPI Mods",
            searchText: "type:smapi"
        )
        let earlierAlphabetically = UserSmartModSet(
            id: "updates",
            name: "Available Updates",
            searchText: "updates:available",
            systemImageName: "arrow.up.circle"
        )

        try UserSmartModSetStore.saveSmartModSets(
            [laterAlphabetically, earlierAlphabetically],
            to: storeURL
        )

        XCTAssertEqual(
            storeURL.path,
            install.modSetDirectoryURL
                .deletingLastPathComponent()
                .appendingPathComponent("Smart Mod Sets.plist")
                .path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))

        let reloaded = try UserSmartModSetStore.loadSmartModSets(from: storeURL)
        XCTAssertEqual(reloaded, [earlierAlphabetically, laterAlphabetically])
    }

    func testMissingStoreLoadsAsEmptyWithoutCreatingModSetPlists() throws {
        let install = try makeInstall()
        let storeURL = StardewInstall.smartModSetStoreURL(
            forModSetDirectory: install.modSetDirectoryURL
        )

        let loaded = try UserSmartModSetStore.loadSmartModSets(from: storeURL)

        XCTAssertEqual(loaded, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertFalse(FileManager.default.directoryExists(at: install.modSetDirectoryURL))
    }

    func testSmartModSetsDoNotChangeRegularModSetStorage() throws {
        let install = try makeInstall()
        let modURL = try makeInstalledMod(name: "Content Patcher", in: install)
        let mods = try ModLibrary.scan(install: install)
        let loadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        let initialSet = try XCTUnwrap(loadedSets.first { $0.id == ModSetStore.initialSetID })
        let regularSet = try ModSetStore.createSet(
            named: "Regular Set",
            from: initialSet,
            existingSets: loadedSets
        )
        try ModSetStore.saveSet(regularSet, install: install)

        let regularSetURL = install.modSetDirectoryURL
            .appendingPathComponent("\(regularSet.id).plist")
        let smartStoreURL = StardewInstall.smartModSetStoreURL(
            forModSetDirectory: install.modSetDirectoryURL
        )

        try UserSmartModSetStore.saveSmartModSets(
            [
                UserSmartModSet(
                    id: "content-patcher",
                    name: "Content Patcher Mods",
                    searchText: "mod:\"Content Patcher\""
                )
            ],
            to: smartStoreURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: modURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: regularSetURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: install.modSetDirectoryURL
                    .appendingPathComponent(StardewInstall.smartModSetFileName)
                    .path
            )
        )

        let reloadedSets = try ModSetStore.loadSets(install: install, currentMods: mods)
        XCTAssertNotNil(reloadedSets.first { $0.id == regularSet.id })
    }

    func testStateStoreLoadsPersistedUserSmartModSets() throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let smartStoreURL = StardewInstall.smartModSetStoreURL(
            forModSetDirectory: install.modSetDirectoryURL
        )
        let smartModSet = UserSmartModSet(
            id: "warnings",
            name: "Warnings",
            searchText: "dependency:optional"
        )
        try UserSmartModSetStore.saveSmartModSets([smartModSet], to: smartStoreURL)

        let stateStore = ModManagerStateStore(
            folderAccess: SecurityScopedFolderAccess(defaults: defaults),
            modSetDirectory: install.modSetDirectoryURL,
            preferences: ModManagerPreferences(defaults: defaults)
        )

        let state = stateStore.initialState(selectedModSetID: ModSetStore.initialSetID)

        XCTAssertEqual(state.userSmartModSets, [smartModSet])
    }

    func testStateStoreSavesUserSmartModSetsWhenPresent() throws {
        let install = try makeInstall()
        let defaults = try makeIsolatedUserDefaults()
        let smartStoreURL = StardewInstall.smartModSetStoreURL(
            forModSetDirectory: install.modSetDirectoryURL
        )
        let stateStore = ModManagerStateStore(
            folderAccess: SecurityScopedFolderAccess(defaults: defaults),
            modSetDirectory: install.modSetDirectoryURL,
            preferences: ModManagerPreferences(defaults: defaults)
        )
        var state = stateStore.initialState(selectedModSetID: ModSetStore.initialSetID)
        state.userSmartModSets = [
            UserSmartModSet(
                id: "updates",
                name: "Updates",
                searchText: "updates:available"
            )
        ]

        stateStore.save(state)

        let reloaded = try UserSmartModSetStore.loadSmartModSets(from: smartStoreURL)
        XCTAssertEqual(reloaded, state.userSmartModSets)
    }

    func testSavingRejectsDuplicateIDsAndNames() throws {
        let storeURL = temporaryDirectory.appendingPathComponent("Smart Mod Sets.plist")

        XCTAssertThrowsError(
            try UserSmartModSetStore.saveSmartModSets(
                [
                    UserSmartModSet(id: "", name: "Updates", searchText: "updates:available")
                ],
                to: storeURL
            )
        ) { error in
            XCTAssertEqual(error as? UserSmartModSetStoreError, .emptyID)
        }

        XCTAssertThrowsError(
            try UserSmartModSetStore.saveSmartModSets(
                [
                    UserSmartModSet(id: "updates", name: "Updates", searchText: "updates:available"),
                    UserSmartModSet(id: "updates", name: "SMAPI", searchText: "type:smapi")
                ],
                to: storeURL
            )
        ) { error in
            XCTAssertEqual(error as? UserSmartModSetStoreError, .duplicateID("updates"))
        }

        XCTAssertThrowsError(
            try UserSmartModSetStore.saveSmartModSets(
                [
                    UserSmartModSet(id: "updates", name: "Updates", searchText: "updates:available"),
                    UserSmartModSet(id: "smapi", name: " updates ", searchText: "type:smapi")
                ],
                to: storeURL
            )
        ) { error in
            XCTAssertEqual(error as? UserSmartModSetStoreError, .duplicateName("updates"))
        }
    }
}
