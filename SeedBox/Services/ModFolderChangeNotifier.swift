import Foundation
@preconcurrency import UserNotifications

protocol ModFolderChangeNotifying {
    func notifyModsFolderChanged()
}

final class UserNotificationModFolderChangeNotifier: NSObject, @unchecked Sendable, ModFolderChangeNotifying, UNUserNotificationCenterDelegate {
    static let shared = UserNotificationModFolderChangeNotifier()

    private override init() {}

    func notifyModsFolderChanged() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                Self.postModsFolderChangedNotification()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { isGranted, _ in
                    if isGranted {
                        Self.postModsFolderChangedNotification()
                    }
                }
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
        content.title = AppStrings.Notifications.modsFolderChangedTitle
        content.body = AppStrings.Notifications.modsFolderChangedBody
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "mods-folder-changed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
