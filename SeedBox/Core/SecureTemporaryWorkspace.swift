import Foundation

enum SecureTemporaryWorkspace {
    static func create(
        in temporaryDirectory: URL,
        prefix: String,
        markerFileName: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let workspaceURL = temporaryDirectory.appendingPathComponent(
            "\(prefix)\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: workspaceURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try Data().write(
                to: workspaceURL.appendingPathComponent(markerFileName),
                options: .atomic
            )
            return workspaceURL
        } catch {
            try? fileManager.removeItem(at: workspaceURL)
            throw error
        }
    }

    static func removeAbandonedDirectories(
        in temporaryDirectory: URL,
        prefix: String,
        markerFileName: String,
        olderThan age: TimeInterval,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) {
        guard let children = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isDirectoryKey,
                .isSymbolicLinkKey
            ],
            options: []
        ) else {
            return
        }
        let cutoffDate = now.addingTimeInterval(-age)

        for childURL in children
        where childURL.lastPathComponent.hasPrefix(prefix) {
            guard let values = try? childURL.resourceValues(
                forKeys: [
                    .contentModificationDateKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey
                ]
            ) else {
                continue
            }
            guard values.isSymbolicLink != true,
                  values.isDirectory == true,
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoffDate
            else {
                continue
            }

            let markerURL = childURL.appendingPathComponent(markerFileName)
            let markerValues = try? markerURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard markerValues?.isRegularFile == true,
                  markerValues?.isSymbolicLink != true
            else {
                continue
            }
            try? fileManager.removeItem(at: childURL)
        }
    }
}
