import Foundation

final class ModManagerSharedStateSync: @unchecked Sendable {
    static let didChangeNotification = Notification.Name("ModManagerDidChangeSharedState")

    private static let senderIDKey = "senderID"

    private let notificationCenter: NotificationCenter
    private let senderID = UUID()
    private var observation: (any NSObjectProtocol)?

    init(
        notificationCenter: NotificationCenter = .default,
        onExternalChange: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.notificationCenter = notificationCenter
        observation = notificationCenter.addObserver(
            forName: Self.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let notificationSenderID = notification.userInfo?[Self.senderIDKey] as? UUID
            Task { @MainActor [weak self, notificationSenderID] in
                guard let self, notificationSenderID != self.senderID else {
                    return
                }

                await onExternalChange()
            }
        }
    }

    func broadcastChange() {
        notificationCenter.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.senderIDKey: senderID]
        )
    }

    deinit {
        if let observation {
            notificationCenter.removeObserver(observation)
        }
    }
}
