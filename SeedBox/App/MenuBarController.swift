import AppKit
import SwiftUI

/// Manages the optional menu bar companion as an `NSStatusItem`, shown or hidden
/// based on the user's setting. The menu content is the SwiftUI
/// ``MenuBarContentView``, hosted via `NSHostingMenu`, so the menu reflects the
/// same shared state as the main window.
///
/// (A SwiftUI `MenuBarExtra` scene would be simpler, but a *conditional*
/// `MenuBarExtra` does not compile on the current toolchain, and the item must
/// be toggleable — hence the AppKit status item.)
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?

    func start() {
        UserDefaults.standard.addObserver(
            self,
            forKeyPath: MenuBarCompanion.enabledDefaultsKey,
            options: [.initial, .new],
            context: nil
        )
    }

    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor in
            self.updateVisibility()
        }
    }

    private func updateVisibility() {
        if UserDefaults.standard.bool(forKey: MenuBarCompanion.enabledDefaultsKey) {
            showStatusItem()
        } else {
            hideStatusItem()
        }
    }

    private func showStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "puzzlepiece.extension.fill",
            accessibilityDescription: AppStrings.App.name
        )
        item.menu = NSHostingMenu(rootView: MenuBarContentView(viewModel: .shared))
        statusItem = item
    }

    private func hideStatusItem() {
        guard let statusItem else {
            return
        }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }
}
