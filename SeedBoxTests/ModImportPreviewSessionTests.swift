import XCTest
@testable import SeedBox

final class ModImportPreviewSessionTests: SeedBoxTestCase {
    func testDiscardRemovesTemporaryExtractionDirectories() async throws {
        let extractionDirectory = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(
            at: extractionDirectory,
            withIntermediateDirectories: true
        )
        try Data("temporary".utf8).write(
            to: extractionDirectory.appendingPathComponent("manifest.json")
        )

        let session = ModImportPreviewSession(
            preview: ModImportPreview(
                sourceURLs: [],
                items: [],
                temporaryExtractionDirectories: [extractionDirectory]
            )
        )

        await session.discard()
        await session.discard()

        XCTAssertFalse(FileManager.default.fileExists(atPath: extractionDirectory.path))
    }

    func testTakingPreviewTransfersCleanupResponsibility() async throws {
        let extractionDirectory = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(
            at: extractionDirectory,
            withIntermediateDirectories: true
        )

        let session = ModImportPreviewSession(
            preview: ModImportPreview(
                sourceURLs: [],
                items: [],
                temporaryExtractionDirectories: [extractionDirectory]
            )
        )

        let preview = try XCTUnwrap(session.takeForInstallation())
        XCTAssertNil(session.takeForInstallation())
        await session.discard()
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractionDirectory.path))

        ModLibrary.discardImportPreview(preview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractionDirectory.path))
    }
}
