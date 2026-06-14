import SwiftUI
import XCTest
@testable import SeedBox

final class ModManagerCommandTests: XCTestCase {
    func testCommandIconsStayCentralized() {
        let expectedIcons: [(ModManagerCommand, String)] = [
            (.createModSet, "folder.badge.plus"),
            (.duplicateModSet, "doc.on.doc"),
            (.renameModSet, "pencil"),
            (.deleteModSet, "folder.badge.minus"),
            (.compareModSet, "rectangle.split.2x1"),
            (.showProblems, "exclamationmark.triangle"),
            (.showActivity, "clock"),
            (.showRestoreHistory, "clock.arrow.circlepath"),
            (.addMods, "square.and.arrow.down"),
            (.restorePreviousVersion, "arrow.uturn.backward"),
            (.showModInspector, "info.circle"),
            (.revealSelectedMod, "eye"),
            (.deleteSelectedMod, "trash"),
            (.pruneExpiredArchives, "archivebox")
        ]

        for (command, systemImage) in expectedIcons {
            XCTAssertEqual(command.systemImage, systemImage)
        }
    }

    func testCommandTitlesStayCentralized() {
        XCTAssertEqual(
            ModManagerCommand.addMods.title(),
            AppStrings.Commands.addMods
        )
        XCTAssertEqual(
            ModManagerCommand.duplicateModSet.title(),
            AppStrings.Commands.duplicateModSet
        )
        XCTAssertEqual(
            ModManagerCommand.showModInspector.title(isShowingModInspector: false),
            AppStrings.Commands.showModDetails
        )
        XCTAssertEqual(
            ModManagerCommand.showModInspector.title(isShowingModInspector: true),
            AppStrings.Toolbar.hideDetails
        )
        XCTAssertEqual(
            ModManagerCommand.revealSelectedMod.title(),
            AppStrings.Commands.revealSelectedModInFinder
        )
        XCTAssertEqual(
            ModManagerCommand.deleteSelectedMod.title(),
            AppStrings.Commands.deleteSelectedMod
        )
    }

    func testCommandShortcutsStayCentralized() {
        assertShortcut(.createModSet, "n", [.command])
        assertShortcut(.addMods, "o", [.command])
        assertShortcut(.chooseModsFolder, "o", [.command, .option])
        assertShortcut(.duplicateModSet, "d", [.command])
        assertShortcut(.deleteModSet, .delete, [.command, .shift])
        assertShortcut(.deleteSelectedMod, .delete, [.command])
        assertShortcut(.renameModSet, .return, [])
        assertShortcut(.showModInspector, "i", [.command])
    }

    private func assertShortcut(
        _ command: ModManagerCommand,
        _ key: KeyEquivalent,
        _ modifiers: EventModifiers,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let shortcut = command.shortcut

        XCTAssertEqual(shortcut?.key, key, file: file, line: line)
        XCTAssertEqual(shortcut?.modifiers, modifiers, file: file, line: line)
    }
}
