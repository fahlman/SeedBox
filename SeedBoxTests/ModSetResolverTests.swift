import XCTest
@testable import SeedBox

final class ModSetResolverTests: SeedBoxTestCase {
    func testResolvedSetNormalizesDisabledFolderTokens() throws {
        let set = ModSet(
            id: "favorites",
            name: "Favorites",
            disabledFolderNames: [" .ContentPatcher ", "contentpatcher", ".SaveBackup"],
            isDefault: false
        )

        let resolvedSet = ModSetResolver.resolve(set)

        XCTAssertEqual(resolvedSet.disabledFolderTokens, [
            "contentpatcher",
            "savebackup"
        ])
    }

    func testResolvedSetDeterminesEnabledStateFromCanonicalFolderName() throws {
        let install = try makeInstall()
        let modURL = install.modDirectoryURL.appendingPathComponent(".ContentPatcher")
        try FileManager.default.createDirectory(at: modURL, withIntermediateDirectories: true)
        try writeManifest(name: "Content Patcher", to: modURL)
        let mod = try XCTUnwrap(try ModLibrary.scan(install: install).first)
        let set = ModSet(
            id: "favorites",
            name: "Favorites",
            disabledFolderNames: ["ContentPatcher"],
            isDefault: false
        )

        XCTAssertFalse(ModSetResolver.resolve(set).isEnabled(mod))
    }
}
