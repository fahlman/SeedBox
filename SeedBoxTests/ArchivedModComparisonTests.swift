import XCTest
@testable import SeedBox

final class ArchivedModComparisonTests: SeedBoxTestCase {
    func testComparesManifestFieldsAgainstInstalledVersion() throws {
        let archived = makeArchived(
            folderName: "ContentPatcher",
            manifest: manifest(
                name: "Content Patcher",
                version: "1.0.0",
                uniqueID: "Pathoschild.ContentPatcher",
                updateKeys: ["Nexus:1915"],
                dependencyIDs: ["SMAPI.ConsoleCommands"]
            )
        )
        let installed = makeInstalled(
            folderName: "ContentPatcher",
            manifest: manifest(
                name: "Content Patcher",
                version: "2.0.0",
                uniqueID: "Pathoschild.ContentPatcher",
                updateKeys: ["Nexus:1915", "GitHub:Pathoschild/StardewMods"],
                dependencyIDs: []
            )
        )

        let comparison = ArchivedModComparison.compare(archived, against: [installed])

        XCTAssertEqual(comparison.installStatus, .installed)
        XCTAssertEqual(comparison.versionRelation, .archivedIsOlder)
        XCTAssertEqual(comparison.installedFolderName, "ContentPatcher")
        XCTAssertTrue(comparison.hasDifferences)

        let changedFields = Set(comparison.differences.map(\.field))
        XCTAssertEqual(changedFields, [.version, .updateKeys, .dependencies])
        XCTAssertFalse(changedFields.contains(.name))
        XCTAssertFalse(changedFields.contains(.uniqueID))
    }

    func testIdenticalManifestsHaveNoDifferences() throws {
        let sharedManifest = manifest(
            name: "Automate",
            version: "1.2.3",
            uniqueID: "Pathoschild.Automate"
        )
        let archived = makeArchived(folderName: "Automate", manifest: sharedManifest)
        let installed = makeInstalled(folderName: "Automate", manifest: sharedManifest)

        let comparison = ArchivedModComparison.compare(archived, against: [installed])

        XCTAssertEqual(comparison.installStatus, .installed)
        XCTAssertEqual(comparison.versionRelation, .same)
        XCTAssertFalse(comparison.hasDifferences)
        XCTAssertTrue(comparison.differences.isEmpty)
    }

    func testNotInstalledArchiveReportsNoComparison() throws {
        let archived = makeArchived(
            folderName: "Removed",
            manifest: manifest(name: "Removed Mod", version: "1.0.0", uniqueID: "Test.Removed")
        )

        let comparison = ArchivedModComparison.compare(archived, against: [])

        XCTAssertEqual(comparison.installStatus, .notInstalled)
        XCTAssertEqual(comparison.versionRelation, .unknown)
        XCTAssertNil(comparison.installedFolderName)
        XCTAssertFalse(comparison.hasDifferences)
        // Every field's installed side is nil when nothing is installed.
        XCTAssertTrue(comparison.fields.allSatisfy { $0.installedValue == nil })
    }

    func testArchivedNewerThanInstalledIsDetected() throws {
        let archived = makeArchived(
            folderName: "SVE",
            manifest: manifest(name: "SVE", version: "2.0.0", uniqueID: "FlashShifter.SVE")
        )
        let installed = makeInstalled(
            folderName: "SVE",
            manifest: manifest(name: "SVE", version: "1.0.0", uniqueID: "FlashShifter.SVE")
        )

        let comparison = ArchivedModComparison.compare(archived, against: [installed])

        XCTAssertEqual(comparison.versionRelation, .archivedIsNewer)
    }

    func testMatchesByFolderWhenUniqueIDDiffers() throws {
        // Same folder, different/blank unique IDs: still matched by folder so a
        // rename or manifest edit does not hide the comparison.
        let archived = makeArchived(
            folderName: "CustomMod",
            manifest: manifest(name: "Custom", version: "1.0.0", uniqueID: nil)
        )
        let installed = makeInstalled(
            folderName: "CustomMod",
            manifest: manifest(name: "Custom Renamed", version: "1.0.0", uniqueID: "New.ID")
        )

        let comparison = ArchivedModComparison.compare(archived, against: [installed])

        XCTAssertEqual(comparison.installStatus, .installed)
        XCTAssertTrue(comparison.differences.contains { $0.field == .name })
        XCTAssertTrue(comparison.differences.contains { $0.field == .uniqueID })
    }

    // MARK: - Helpers

    private func manifest(
        name: String,
        version: String,
        uniqueID: String?,
        updateKeys: [String] = [],
        dependencyIDs: [String] = []
    ) -> ModManifest {
        ModManifest(
            name: name,
            author: "Test Author",
            version: version,
            description: nil,
            uniqueID: uniqueID,
            entryDll: nil,
            minimumApiVersion: nil,
            updateKeys: updateKeys.isEmpty ? nil : updateKeys,
            contentPackFor: nil,
            dependencies: dependencyIDs.isEmpty
                ? nil
                : dependencyIDs.map {
                    ModManifest.Dependency(uniqueID: $0, isRequired: true, minimumVersion: nil)
                }
        )
    }

    private func makeArchived(folderName: String, manifest: ModManifest) -> ArchivedModInfo {
        let container = URL(fileURLWithPath: "/tmp/archive/\(folderName)")
        return ArchivedModInfo(
            url: container.appendingPathComponent(folderName),
            containerURL: container,
            folderName: folderName,
            reason: .updated,
            archivedDate: Date(timeIntervalSince1970: 0),
            manifest: manifest
        )
    }

    private func makeInstalled(folderName: String, manifest: ModManifest) -> ModInfo {
        ModInfo(
            folderName: folderName,
            url: URL(fileURLWithPath: "/tmp/mods/\(folderName)"),
            isEnabled: true,
            manifest: manifest
        )
    }
}
