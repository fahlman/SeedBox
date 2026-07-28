import AppIntents
import Foundation

enum SeedBoxShortcutRequest: String, CaseIterable, Identifiable, Sendable {
    case showProblems
    case showWarnings
    case showErrors
    case showActivity
    case showRestoreHistory

    var id: String { rawValue }

    var route: SeedBoxRoute {
        switch self {
        case .showProblems:
            return .problems
        case .showWarnings:
            return .warnings
        case .showErrors:
            return .errors
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
    private var pendingRoute: SeedBoxRoute?

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

    /// Requests navigation to an arbitrary route (e.g. from a Spotlight result).
    func request(route: SeedBoxRoute) {
        pendingRoute = route
        notificationCenter.post(
            name: Self.didRequestShortcutNotification,
            object: nil
        )
    }

    func consumePendingRequest() -> SeedBoxShortcutRequest? {
        defer {
            pendingRequest = nil
        }
        return pendingRequest
    }

    func consumePendingRoute() -> SeedBoxRoute? {
        defer {
            pendingRoute = nil
        }
        return pendingRoute
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

struct OpenWarningsShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Warnings"
    static let description = IntentDescription("Open Seed Box and show mods with warnings.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            SeedBoxShortcutRouter.shared.request(.showWarnings)
        }
        return .result()
    }
}

struct OpenErrorsShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Errors"
    static let description = IntentDescription("Open Seed Box and show mods with errors.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            SeedBoxShortcutRouter.shared.request(.showErrors)
        }
        return .result()
    }
}

/// An App Intents entity for a Mod Set, so Shortcuts can offer the user's Mod
/// Sets as a parameter. Backed by the live library; stale ids fail gracefully
/// because the route dispatcher ignores unknown sets.
struct ModSetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mod Set"
    static let defaultQuery = ModSetEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(modSet: ModSet) {
        self.init(id: modSet.id, name: modSet.name)
    }
}

struct ModSetEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [ModSetEntity.ID]) async throws -> [ModSetEntity] {
        ModManagerViewModel.shared.state.modSets
            .filter { identifiers.contains($0.id) }
            .map(ModSetEntity.init(modSet:))
    }

    @MainActor
    func suggestedEntities() async throws -> [ModSetEntity] {
        ModManagerViewModel.shared.state.modSets.map(ModSetEntity.init(modSet:))
    }
}

struct OpenModSetShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Mod Set"
    static let description = IntentDescription("Open Seed Box and select a specific Mod Set.")
    static let openAppWhenRun = true

    @Parameter(title: "Mod Set")
    var modSet: ModSetEntity

    func perform() async throws -> some IntentResult {
        let id = modSet.id
        await MainActor.run {
            SeedBoxShortcutRouter.shared.request(route: .modSet(id: id))
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
            intent: OpenWarningsShortcutIntent(),
            phrases: [
                "Show warnings in \(.applicationName)",
                "Open \(.applicationName) warnings"
            ],
            shortTitle: "Warnings",
            systemImageName: "exclamationmark.triangle"
        )
        AppShortcut(
            intent: OpenErrorsShortcutIntent(),
            phrases: [
                "Show errors in \(.applicationName)",
                "Open \(.applicationName) errors"
            ],
            shortTitle: "Errors",
            systemImageName: "xmark.octagon"
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
