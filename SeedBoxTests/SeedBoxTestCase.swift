import XCTest
@testable import SeedBox

class SeedBoxTestCase: XCTestCase {
    var temporaryDirectory: URL!

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

    func makeInstall() throws -> StardewInstall {
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

    func makeModsDirectory() throws -> URL {
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

    @MainActor
    func makeIsolatedUserDefaults() throws -> UserDefaults {
        let suiteName = "SeedBoxTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func assertSameFileURL(
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

    func modEnabledStates(in mods: [ModInfo]) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: mods.map { ($0.displayName, $0.isEnabled) })
    }

    func writeManifest(
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
