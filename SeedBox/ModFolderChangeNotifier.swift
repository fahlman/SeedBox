import Foundation
@preconcurrency import UserNotifications

protocol ModFolderChangeNotifying {
    func requestAuthorization()
    func notifyModsFolderChanged()
}

final class UserNotificationModFolderChangeNotifier: NSObject, @unchecked Sendable, ModFolderChangeNotifying, UNUserNotificationCenterDelegate {
    static let shared = UserNotificationModFolderChangeNotifier()

    private override init() {}

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyModsFolderChanged() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                Self.postModsFolderChangedNotification()
            default:
                break
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private static func postModsFolderChangedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Mods Folder Changed"
        content.body = "Seed Box refreshed the mod list."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "mods-folder-changed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
