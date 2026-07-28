import XCTest
@testable import SeedBox

final class SeedBoxSetDocumentTests: SeedBoxTestCase {
    func testExportsRegularModSetWithEnrichedMetadata() throws {
        let mods = [
            makeMod(folder: "ContentPatcher", name: "Content Patcher", uniqueID: "Pathoschild.ContentPatcher", version: "2.0.0"),
            makeMod(folder: "Automate", name: "Automate", uniqueID: "Pathoschild.Automate", version: "1.2.3")
        ]

        let document = SeedBoxSetCodec.makeDocument(
            name: "My Set",
            disabledFolderNames: [".ContentPatcher", "Unknown Mod"],
            installedMods: mods
        )

        XCTAssertEqual(document.schemaVersion, SeedBoxSetDocument.currentSchemaVersion)
        XCTAssertEqual(document.kind, SeedBoxSetDocument.modSetKind)
        XCTAssertEqual(document.modSet.name, "My Set")
        // Folder names are canonicalized (dot stripped) and sorted.
        XCTAssertEqual(document.modSet.disabledMods.map(\.folderName), ["ContentPatcher", "Unknown Mod"])

        let cp = try XCTUnwrap(document.modSet.disabledMods.first { $0.folderName == "ContentPatcher" })
        XCTAssertEqual(cp.modName, "Content Patcher")
        XCTAssertEqual(cp.uniqueID, "Pathoschild.ContentPatcher")
        XCTAssertEqual(cp.version, "2.0.0")

        // A folder with no matching installed mod still exports, without metadata.
        let unknown = try XCTUnwrap(document.modSet.disabledMods.first { $0.folderName == "Unknown Mod" })
        XCTAssertNil(unknown.modName)
        XCTAssertNil(unknown.uniqueID)
    }

    func testRoundTripsThroughEncodeAndDecode() throws {
        let mods = [makeMod(folder: "ContentPatcher", name: "Content Patcher", uniqueID: "Pathoschild.ContentPatcher", version: "2.0.0")]
        let document = SeedBoxSetCodec.makeDocument(
            name: "Favorites",
            disabledFolderNames: ["ContentPatcher"],
            installedMods: mods
        )

        let data = try SeedBoxSetCodec.encode(document)
        let decoded = try SeedBoxSetCodec.decode(data)

        XCTAssertEqual(decoded, document)

        // And it maps back to a usable Mod Set with a fresh id.
        let set = SeedBoxSetCodec.modSet(from: decoded, id: "imported")
        XCTAssertEqual(set.id, "imported")
        XCTAssertEqual(set.name, "Favorites")
        XCTAssertEqual(set.disabledFolderNames, ["ContentPatcher"])
    }

    func testExportContainsNoPrivatePathsOrSensitiveData() throws {
        let mods = [makeMod(
            folder: "ContentPatcher",
            name: "Content Patcher",
            uniqueID: "Pathoschild.ContentPatcher",
            version: "2.0.0",
            url: URL(fileURLWithPath: "/Users/someone/Library/Application Support/Stardew/Mods/ContentPatcher")
        )]

        let data = try SeedBoxSetCodec.encode(
            SeedBoxSetCodec.makeDocument(name: "Set", disabledFolderNames: ["ContentPatcher"], installedMods: mods)
        )
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.lowercased().contains("bookmark"))
        XCTAssertFalse(json.contains("Application Support"))
    }

    func testDecodeRejectsMalformedData() throws {
        let data = Data("{ not json".utf8)
        XCTAssertThrowsError(try SeedBoxSetCodec.decode(data)) { error in
            XCTAssertEqual(error as? SeedBoxSetError, .malformedData)
        }
    }

    func testDecodeRejectsUnsupportedKind() throws {
        let data = Data(#"{"schemaVersion":1,"kind":"smartSet","generator":"Seed Box","modSet":{"name":"x","disabledMods":[]}}"#.utf8)
        XCTAssertThrowsError(try SeedBoxSetCodec.decode(data)) { error in
            XCTAssertEqual(error as? SeedBoxSetError, .unsupportedKind("smartSet"))
        }
    }

    func testDecodeRejectsFutureVersion() throws {
        let future = SeedBoxSetDocument.currentSchemaVersion + 1
        let data = Data(#"{"schemaVersion":\#(future),"kind":"modSet","generator":"Seed Box","modSet":{"name":"x","disabledMods":[]}}"#.utf8)
        XCTAssertThrowsError(try SeedBoxSetCodec.decode(data)) { error in
            XCTAssertEqual(error as? SeedBoxSetError, .futureVersion(future))
        }
    }

    func testDecodeRejectsUnsupportedOldVersion() throws {
        let data = Data(#"{"schemaVersion":0,"kind":"modSet","generator":"Seed Box","modSet":{"name":"x","disabledMods":[]}}"#.utf8)
        XCTAssertThrowsError(try SeedBoxSetCodec.decode(data)) { error in
            XCTAssertEqual(error as? SeedBoxSetError, .unsupportedVersion(0))
        }
    }

    func testDecodeRejectsMissingName() throws {
        let data = Data(#"{"schemaVersion":1,"kind":"modSet","generator":"Seed Box","modSet":{"name":"   ","disabledMods":[]}}"#.utf8)
        XCTAssertThrowsError(try SeedBoxSetCodec.decode(data)) { error in
            XCTAssertEqual(error as? SeedBoxSetError, .missingName)
        }
    }

    func testDecodeIgnoresUnknownForwardCompatibleFields() throws {
        // A same-version file with extra fields decodes (fields ignored).
        let data = Data(#"{"schemaVersion":1,"kind":"modSet","generator":"Seed Box","futureField":true,"modSet":{"name":"x","disabledMods":[],"extra":42}}"#.utf8)
        let decoded = try SeedBoxSetCodec.decode(data)
        XCTAssertEqual(decoded.modSet.name, "x")
    }

    func testImportedModSetAvoidsNameCollisions() throws {
        let existing = [
            ModSet(id: "a", name: "Favorites", disabledFolderNames: []),
            ModSet(id: "b", name: "Favorites 2", disabledFolderNames: [])
        ]
        let document = SeedBoxSetCodec.makeDocument(
            name: "Favorites",
            disabledFolderNames: ["ContentPatcher"],
            installedMods: []
        )

        let imported = SeedBoxSetCodec.importedModSet(from: document, existingSets: existing)
        XCTAssertEqual(imported.name, "Favorites 3")
        XCTAssertEqual(imported.disabledFolderNames, ["ContentPatcher"])
        XCTAssertFalse(existing.contains { $0.id == imported.id })
    }

    func testImportedModSetKeepsUniqueNameUnchanged() throws {
        let existing = [ModSet(id: "a", name: "Favorites", disabledFolderNames: [])]
        let document = SeedBoxSetCodec.makeDocument(
            name: "Stardew Valley Expanded",
            disabledFolderNames: [],
            installedMods: []
        )

        let imported = SeedBoxSetCodec.importedModSet(from: document, existingSets: existing)
        XCTAssertEqual(imported.name, "Stardew Valley Expanded")
    }

    private func makeMod(
        folder: String,
        name: String,
        uniqueID: String,
        version: String,
        url: URL? = nil
    ) -> ModInfo {
        ModInfo(
            folderName: folder,
            url: url ?? URL(fileURLWithPath: "/tmp/\(folder)"),
            isEnabled: true,
            manifest: ModManifest(
                name: name,
                author: "Author",
                version: version,
                description: nil,
                uniqueID: uniqueID,
                entryDll: nil,
                minimumApiVersion: nil,
                updateKeys: nil,
                contentPackFor: nil,
                dependencies: nil
            )
        )
    }
}
