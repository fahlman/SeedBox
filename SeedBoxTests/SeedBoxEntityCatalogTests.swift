import XCTest
@testable import SeedBox

final class SeedBoxEntityCatalogTests: SeedBoxTestCase {
    func testGeneratesEntitiesForEachKindWithStableIdentifiers() throws {
        let mod = makeMod(folder: "ContentPatcher", name: "Content Patcher", version: "2.0.0")
        let set = ModSet(id: "favorites", name: "Favorites", disabledFolderNames: [])
        let smart = UserSmartModSet(id: "recent", name: "Recent", searchText: "")
        let state = try makeState(mods: [mod], modSets: [set], userSmartModSets: [smart])

        let entities = SeedBoxEntityCatalog.entities(from: state)
        let byID = Dictionary(uniqueKeysWithValues: entities.map { ($0.systemIdentifier, $0) })

        // One identity per object, namespaced and stable.
        XCTAssertEqual(byID["seedbox:mod:\(mod.id)"]?.route, .mod(id: mod.id))
        XCTAssertEqual(byID["seedbox:modSet:favorites"]?.route, .modSet(id: "favorites"))
        XCTAssertEqual(byID["seedbox:userSmartModSet:recent"]?.route, .userSmartModSet(id: "recent"))
        XCTAssertEqual(byID["seedbox:builtInSmartModSet:allMods"]?.route, .smartModSet(.allMods))
        XCTAssertEqual(byID["seedbox:destination:problems"]?.route, .problems)

        // Regenerating from the same state yields identical identities.
        let again = SeedBoxEntityCatalog.entities(from: state)
        XCTAssertEqual(entities.map(\.systemIdentifier), again.map(\.systemIdentifier))
    }

    func testRouteMappingRoundTripsForRepresentativeKinds() throws {
        XCTAssertEqual(
            SeedBoxEntityCatalog.route(forSystemIdentifier: "seedbox:mod:a#b"),
            .mod(id: "a#b")
        )
        XCTAssertEqual(
            SeedBoxEntityCatalog.route(forSystemIdentifier: "seedbox:modSet:favorites"),
            .modSet(id: "favorites")
        )
        XCTAssertEqual(
            SeedBoxEntityCatalog.route(forSystemIdentifier: "seedbox:builtInSmartModSet:warnings"),
            .smartModSet(.warnings)
        )
        XCTAssertEqual(
            SeedBoxEntityCatalog.route(forSystemIdentifier: "seedbox:destination:restoreHistory"),
            .restoreHistory
        )
    }

    func testRouteMappingRejectsUnknownIdentifiers() throws {
        XCTAssertNil(SeedBoxEntityCatalog.route(forSystemIdentifier: "other:mod:x"))
        XCTAssertNil(SeedBoxEntityCatalog.route(forSystemIdentifier: "seedbox:bogus:x"))
        XCTAssertNil(SeedBoxEntityCatalog.route(forSystemIdentifier: "seedbox:mod:"))
        XCTAssertNil(SeedBoxEntityCatalog.route(forSystemIdentifier: "seedbox:builtInSmartModSet:notARealSet"))
        XCTAssertNil(SeedBoxEntityCatalog.route(forSystemIdentifier: "seedbox:destination:diagnostics"))
    }

    func testDeletedObjectsDropOutOfTheCatalog() throws {
        let set = ModSet(id: "favorites", name: "Favorites", disabledFolderNames: [])
        let withSet = try makeState(mods: [], modSets: [set], userSmartModSets: [])
        XCTAssertTrue(SeedBoxEntityCatalog.entities(from: withSet).contains { $0.systemIdentifier == "seedbox:modSet:favorites" })

        let withoutSet = try makeState(mods: [], modSets: [], userSmartModSets: [])
        XCTAssertFalse(SeedBoxEntityCatalog.entities(from: withoutSet).contains { $0.systemIdentifier == "seedbox:modSet:favorites" })
    }

    func testEntityMetadataContainsNoPrivatePaths() throws {
        let mod = ModInfo(
            folderName: "ContentPatcher",
            url: URL(fileURLWithPath: "/Users/someone/Library/Stardew/Mods/ContentPatcher"),
            isEnabled: true,
            manifest: manifest(name: "Content Patcher", version: "2.0.0")
        )
        let state = try makeState(mods: [mod], modSets: [], userSmartModSets: [])

        for entity in SeedBoxEntityCatalog.entities(from: state) {
            let text = ([entity.title, entity.subtitle].compactMap { $0 } + entity.keywords)
                .joined(separator: " ")
            XCTAssertFalse(text.contains("/Users/"), "Entity leaked a path: \(text)")
            XCTAssertFalse(text.contains("Library"), "Entity leaked a path: \(text)")
        }
    }

    func testSurfacesDescribeWhereEachKindAppears() throws {
        let mod = makeMod(folder: "ContentPatcher", name: "Content Patcher", version: "2.0.0")
        let set = ModSet(id: "favorites", name: "Favorites", disabledFolderNames: [])
        let state = try makeState(mods: [mod], modSets: [set], userSmartModSets: [])
        let byID = Dictionary(
            uniqueKeysWithValues: SeedBoxEntityCatalog.entities(from: state).map { ($0.systemIdentifier, $0) }
        )

        XCTAssertTrue(byID["seedbox:mod:\(mod.id)"]?.surfaces.contains(.spotlight) == true)
        XCTAssertTrue(byID["seedbox:modSet:favorites"]?.surfaces.contains(.shortcuts) == true)
        // Destinations are menu-bar actions, not Spotlight results.
        XCTAssertFalse(byID["seedbox:destination:problems"]?.surfaces.contains(.spotlight) == true)
        XCTAssertTrue(byID["seedbox:destination:problems"]?.surfaces.contains(.menuBar) == true)
    }

    // MARK: - Helpers

    private func makeMod(folder: String, name: String, version: String) -> ModInfo {
        ModInfo(
            folderName: folder,
            url: URL(fileURLWithPath: "/tmp/\(folder)"),
            isEnabled: true,
            manifest: manifest(name: name, version: version)
        )
    }

    private func manifest(name: String, version: String) -> ModManifest {
        ModManifest(
            name: name,
            author: "Author",
            version: version,
            description: nil,
            uniqueID: "Test.\(name.replacingOccurrences(of: " ", with: ""))",
            entryDll: nil,
            minimumApiVersion: nil,
            updateKeys: nil,
            contentPackFor: nil,
            dependencies: nil
        )
    }

    private func makeState(
        mods: [ModInfo],
        modSets: [ModSet],
        userSmartModSets: [UserSmartModSet]
    ) throws -> ModManagerState {
        let install = try makeInstall()
        return ModManagerState(
            modsDirectoryPath: install.modDirectoryURL.path,
            status: install.status(),
            hasSavedFolderAccess: true,
            mods: mods,
            invalidModFolders: [],
            archivedMods: [],
            archiveSummary: ModArchiveSummary(),
            archiveSettings: ArchiveSettings(
                automaticallyPrunesExpiredArchives: false,
                retentionDays: ArchiveSettings.defaultRetentionDays
            ),
            hasLoadedMods: true,
            modSets: modSets,
            userSmartModSets: userSmartModSets,
            selectedModSetID: ModSetStore.defaultSetID,
            appliedModSetID: nil,
            activityStatus: nil,
            auditTrail: AuditTrailState(
                logPath: install.modSetDirectory.appendingPathComponent("Audit Log.json").path,
                recentEntries: [],
                lastErrorMessage: nil
            ),
            pendingSourceCleanupOffer: nil
        )
    }
}
