import AppIntents
import Foundation

enum SeedBoxShortcutRequest: String, CaseIterable, Identifiable, Sendable {
    case showProblems
    case showActivity
    case showRestoreHistory

    var id: String { rawValue }

    var route: SeedBoxRoute {
        switch self {
        case .showProblems:
            return .problems
        case .showActivity:
            return .activity
        case .showRestoreHistory:
            return .restoreHistory
        }
    }
}

@MainActor
final class SeedBoxShortcutRouter {
    static let shared = SeedBoxShortcutRouter()
    static let didRequestShortcutNotification = Notification.Name("SeedBoxShortcutRouterDidRequestShortcut")

    private let notificationCenter: NotificationCenter
    private var pendingRequest: SeedBoxShortcutRequest?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func request(_ request: SeedBoxShortcutRequest) {
        pendingRequest = request
        notificationCenter.post(
            name: Self.didRequestShortcutNotification,
            object: request
        )
    }

    func consumePendingRequest() -> SeedBoxShortcutRequest? {
        defer {
            pendingRequest = nil
        }
        return pendingRequest
    }
}

struct OpenProblemsShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Problems"
    static let description = IntentDescription("Open Seed Box and show mod errors, warnings, duplicates, and last-session problems.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            SeedBoxShortcutRouter.shared.request(.showProblems)
        }
        return .result()
    }
}

struct OpenActivityShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Activity"
    static let description = IntentDescription("Open Seed Box and show recent mod and Mod Set activity.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            SeedBoxShortcutRouter.shared.request(.showActivity)
        }
        return .result()
    }
}

struct OpenRestoreHistoryShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Restore History"
    static let description = IntentDescription("Open Seed Box and show archived mods that can be restored or permanently removed.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            SeedBoxShortcutRouter.shared.request(.showRestoreHistory)
        }
        return .result()
    }
}

struct SeedBoxAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor {
        .grayGreen
    }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenProblemsShortcutIntent(),
            phrases: [
                "Show problems in \(.applicationName)",
                "Open \(.applicationName) problems"
            ],
            shortTitle: "Problems",
            systemImageName: "exclamationmark.triangle"
        )
        AppShortcut(
            intent: OpenActivityShortcutIntent(),
            phrases: [
                "Show activity in \(.applicationName)",
                "Open \(.applicationName) activity"
            ],
            shortTitle: "Activity",
            systemImageName: "clock"
        )
        AppShortcut(
            intent: OpenRestoreHistoryShortcutIntent(),
            phrases: [
                "Show restore history in \(.applicationName)",
                "Open \(.applicationName) restore history"
            ],
            shortTitle: "Restore History",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
