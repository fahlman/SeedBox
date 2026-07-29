import Foundation

struct FileMoveOperation: Codable, Equatable, Sendable {
    var sourceURL: URL
    var destinationURL: URL
}

struct FileMoveTransactionError: Error, LocalizedError, Sendable {
    var primaryErrorDescription: String
    var rollbackErrorDescriptions: [String]

    var errorDescription: String? {
        guard !rollbackErrorDescriptions.isEmpty else {
            return primaryErrorDescription
        }

        return [
            primaryErrorDescription,
            "Seed Box could not completely restore the previous folder state:",
            rollbackErrorDescriptions.joined(separator: "\n")
        ]
        .joined(separator: "\n")
    }
}

enum FileMoveTransaction {
    static let journalFileName = ".seedbox-file-transaction.plist"

    private static let schemaVersion = 1

    private struct Journal: Codable {
        var schemaVersion: Int
        var operations: [FileMoveOperation]
    }

    static func perform(
        _ requestedOperations: [FileMoveOperation],
        journalDirectoryURL: URL,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) throws {
        guard !requestedOperations.isEmpty else {
            return
        }

        guard fileManager.directoryExists(at: journalDirectoryURL) else {
            throw CocoaError(
                .fileNoSuchFile,
                userInfo: [NSFilePathErrorKey: journalDirectoryURL.path]
            )
        }
        try recoverIfNeeded(
            in: journalDirectoryURL,
            fileManager: fileManager,
            moveItem: moveItem
        )

        let operations = requestedOperations.map {
            FileMoveOperation(
                sourceURL: $0.sourceURL.standardizedFileURL,
                destinationURL: $0.destinationURL.standardizedFileURL
            )
        }
        try preflight(operations, fileManager: fileManager)

        let journalURL = journalURL(in: journalDirectoryURL)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let journalData = try encoder.encode(
            Journal(schemaVersion: schemaVersion, operations: operations)
        )
        try journalData.write(to: journalURL, options: .atomic)

        let mover = moveItem ?? { sourceURL, destinationURL in
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
        var completedOperations: [FileMoveOperation] = []

        do {
            for operation in operations {
                try mover(operation.sourceURL, operation.destinationURL)
                completedOperations.append(operation)
            }
        } catch {
            let rollbackErrors = rollback(
                completedOperations,
                fileManager: fileManager,
                moveItem: mover
            )
            let cleanupErrors = removeJournalIfRollbackCompleted(
                at: journalURL,
                rollbackErrors: rollbackErrors,
                fileManager: fileManager
            )
            throw FileMoveTransactionError(
                primaryErrorDescription: error.localizedDescription,
                rollbackErrorDescriptions: rollbackErrors + cleanupErrors
            )
        }

        do {
            try fileManager.removeItem(at: journalURL)
        } catch {
            let rollbackErrors = rollback(
                completedOperations,
                fileManager: fileManager,
                moveItem: mover
            )
            let cleanupErrors = removeJournalIfRollbackCompleted(
                at: journalURL,
                rollbackErrors: rollbackErrors,
                fileManager: fileManager
            )
            throw FileMoveTransactionError(
                primaryErrorDescription: error.localizedDescription,
                rollbackErrorDescriptions: rollbackErrors + cleanupErrors
            )
        }
    }

    static func recoverIfNeeded(
        in journalDirectoryURL: URL,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) throws {
        let journalURL = journalURL(in: journalDirectoryURL)
        guard fileManager.fileExists(atPath: journalURL.path) else {
            return
        }

        let data = try Data(contentsOf: journalURL)
        let journal = try PropertyListDecoder().decode(Journal.self, from: data)
        guard journal.schemaVersion == schemaVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let mover = moveItem ?? { sourceURL, destinationURL in
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
        var recoveryErrors: [String] = []

        for operation in journal.operations.reversed() {
            let sourceExists = fileManager.fileExists(atPath: operation.sourceURL.path)
            let destinationExists = fileManager.fileExists(atPath: operation.destinationURL.path)

            switch (sourceExists, destinationExists) {
            case (true, false):
                continue
            case (false, true):
                do {
                    try mover(operation.destinationURL, operation.sourceURL)
                } catch {
                    recoveryErrors.append(error.localizedDescription)
                }
            case (true, true):
                recoveryErrors.append(
                    "Both \(operation.sourceURL.path) and \(operation.destinationURL.path) exist."
                )
            case (false, false):
                recoveryErrors.append(
                    "Neither \(operation.sourceURL.path) nor \(operation.destinationURL.path) exists."
                )
            }
        }

        guard recoveryErrors.isEmpty else {
            throw FileMoveTransactionError(
                primaryErrorDescription: "Seed Box found an interrupted folder operation.",
                rollbackErrorDescriptions: recoveryErrors
            )
        }

        try fileManager.removeItem(at: journalURL)
    }

    private static func preflight(
        _ operations: [FileMoveOperation],
        fileManager: FileManager
    ) throws {
        let sourcePaths = operations.map { $0.sourceURL.path }
        let destinationPaths = operations.map { $0.destinationURL.path }
        guard Set(sourcePaths).count == sourcePaths.count,
              Set(destinationPaths).count == destinationPaths.count
        else {
            throw CocoaError(.fileWriteFileExists)
        }

        let sourceIndices = Dictionary(
            uniqueKeysWithValues: sourcePaths.enumerated().map { ($0.element, $0.offset) }
        )

        for (index, operation) in operations.enumerated() {
            guard operation.sourceURL != operation.destinationURL else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            guard fileManager.fileExists(atPath: operation.sourceURL.path) else {
                throw CocoaError(
                    .fileNoSuchFile,
                    userInfo: [NSFilePathErrorKey: operation.sourceURL.path]
                )
            }

            let destinationExists = fileManager.fileExists(atPath: operation.destinationURL.path)
            if destinationExists {
                guard let sourceIndex = sourceIndices[operation.destinationURL.path],
                      sourceIndex < index
                else {
                    throw CocoaError(
                        .fileWriteFileExists,
                        userInfo: [NSFilePathErrorKey: operation.destinationURL.path]
                    )
                }
            }

            let destinationParentURL = operation.destinationURL.deletingLastPathComponent()
            guard fileManager.directoryExists(at: destinationParentURL) else {
                throw CocoaError(
                    .fileNoSuchFile,
                    userInfo: [NSFilePathErrorKey: destinationParentURL.path]
                )
            }
        }
    }

    private static func rollback(
        _ completedOperations: [FileMoveOperation],
        fileManager: FileManager,
        moveItem: (URL, URL) throws -> Void
    ) -> [String] {
        var errors: [String] = []
        for operation in completedOperations.reversed() {
            do {
                guard !fileManager.fileExists(atPath: operation.sourceURL.path),
                      fileManager.fileExists(atPath: operation.destinationURL.path)
                else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try moveItem(operation.destinationURL, operation.sourceURL)
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        return errors
    }

    private static func removeJournalIfRollbackCompleted(
        at journalURL: URL,
        rollbackErrors: [String],
        fileManager: FileManager
    ) -> [String] {
        guard rollbackErrors.isEmpty else {
            return []
        }

        do {
            try fileManager.removeItem(at: journalURL)
            return []
        } catch {
            return [error.localizedDescription]
        }
    }

    private static func journalURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(journalFileName, isDirectory: false)
    }
}
