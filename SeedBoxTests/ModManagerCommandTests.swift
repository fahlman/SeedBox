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

    func testPlacementSpecificTitlesPreserveMenuAndToolbarWording() {
        XCTAssertEqual(
            ModManagerCommand.addMods.title(for: .menu),
            AppStrings.Commands.addMods
        )
        XCTAssertEqual(
            ModManagerCommand.addMods.title(for: .toolbar),
            AppStrings.Toolbar.addMods
        )
        XCTAssertEqual(
            ModManagerCommand.duplicateModSet.title(for: .menu),
            AppStrings.Commands.duplicateModSet
        )
        XCTAssertEqual(
            ModManagerCommand.duplicateModSet.title(for: .toolbar),
            AppStrings.Toolbar.duplicateSet
        )
        XCTAssertEqual(
            ModManagerCommand.showModInspector.title(
                for: .menu,
                isShowingModInspector: false
            ),
            AppStrings.Commands.showModDetails
        )
        XCTAssertEqual(
            ModManagerCommand.showModInspector.title(
                for: .toolbar,
                isShowingModInspector: false
            ),
            AppStrings.Toolbar.showDetails
        )
        XCTAssertEqual(
            ModManagerCommand.showModInspector.title(
                for: .menu,
                isShowingModInspector: true
            ),
            AppStrings.Toolbar.hideDetails
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
