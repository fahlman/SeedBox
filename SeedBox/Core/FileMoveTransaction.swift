import Darwin
import Foundation

struct FileMoveOperation: Codable, Equatable, Sendable {
    var sourceURL: URL
    var destinationURL: URL
}

struct FileMoveTransactionContext: Equatable, Sendable {
    let journalDirectoryURL: URL
    let allowedRootPaths: [String]
    let journalURL: URL

    init(journalDirectoryURL: URL, allowedRootURLs: [URL]) {
        precondition(!allowedRootURLs.isEmpty)

        self.journalDirectoryURL = journalDirectoryURL
            .standardizedFileURL
        allowedRootPaths = Array(
            Set(allowedRootURLs.map {
                FileMoveTransaction.canonicalPathResolvingExistingAncestor(for: $0)
            })
        )
        .sorted()

        let identity = StableDigest.sha256Hex(components: allowedRootPaths)
        journalURL = self.journalDirectoryURL
            .appendingPathComponent("file-move-\(identity).plist", isDirectory: false)
    }
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

enum FileMoveTransactionSecurityError: Error, Equatable, LocalizedError, Sendable {
    case invalidJournal
    case journalTooLarge
    case tooManyOperations
    case rootsDoNotMatch
    case operationOutsideApprovedFolders
    case symbolicLinkEndpoint
    case nonDirectoryEndpoint

    var errorDescription: String? {
        switch self {
        case .invalidJournal:
            "Seed Box found an invalid interrupted file operation."
        case .journalTooLarge:
            "Seed Box refused an unexpectedly large interrupted file operation."
        case .tooManyOperations:
            "Seed Box refused an interrupted file operation with too many changes."
        case .rootsDoNotMatch:
            "Seed Box refused an interrupted file operation for a different Mods folder."
        case .operationOutsideApprovedFolders:
            "Seed Box refused a file operation outside its approved Mods and archive folders."
        case .symbolicLinkEndpoint:
            "Seed Box refused a file operation through a symbolic link."
        case .nonDirectoryEndpoint:
            "Seed Box refused a file operation that did not reference a mod folder."
        }
    }
}

enum FileMoveTransaction {
    private static let schemaVersion = 2
    private static let maximumJournalByteCount: Int64 = 4 * 1024 * 1024
    private static let maximumOperationCount = 10_000

    private struct Journal: Codable {
        var schemaVersion: Int
        var allowedRootPaths: [String]
        var operations: [FileMoveOperation]
    }

    static func perform(
        _ requestedOperations: [FileMoveOperation],
        context: FileMoveTransactionContext,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) throws {
        guard !requestedOperations.isEmpty else {
            return
        }

        try prepareJournalDirectory(context.journalDirectoryURL, fileManager: fileManager)
        try recoverIfNeeded(
            context: context,
            fileManager: fileManager,
            moveItem: moveItem
        )

        let operations = requestedOperations.map {
            FileMoveOperation(
                sourceURL: $0.sourceURL.standardizedFileURL,
                destinationURL: $0.destinationURL.standardizedFileURL
            )
        }
        try validateSecurityBoundary(
            operations,
            context: context,
            fileManager: fileManager
        )
        try preflight(operations, fileManager: fileManager)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let journalData = try encoder.encode(
            Journal(
                schemaVersion: schemaVersion,
                allowedRootPaths: context.allowedRootPaths,
                operations: operations
            )
        )
        guard journalData.count <= maximumJournalByteCount else {
            throw FileMoveTransactionSecurityError.journalTooLarge
        }
        try journalData.write(to: context.journalURL, options: .atomic)

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
                at: context.journalURL,
                rollbackErrors: rollbackErrors,
                fileManager: fileManager
            )
            throw FileMoveTransactionError(
                primaryErrorDescription: error.localizedDescription,
                rollbackErrorDescriptions: rollbackErrors + cleanupErrors
            )
        }

        do {
            try fileManager.removeItem(at: context.journalURL)
        } catch {
            let rollbackErrors = rollback(
                completedOperations,
                fileManager: fileManager,
                moveItem: mover
            )
            let cleanupErrors = removeJournalIfRollbackCompleted(
                at: context.journalURL,
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
        context: FileMoveTransactionContext,
        fileManager: FileManager = .default,
        moveItem: ((URL, URL) throws -> Void)? = nil
    ) throws {
        guard fileManager.fileExists(atPath: context.journalURL.path) else {
            return
        }

        let values = try context.journalURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isSymbolicLink != true else {
            throw FileMoveTransactionSecurityError.symbolicLinkEndpoint
        }
        guard values.isRegularFile == true else {
            throw FileMoveTransactionSecurityError.invalidJournal
        }
        guard Int64(values.fileSize ?? 0) <= maximumJournalByteCount else {
            throw FileMoveTransactionSecurityError.journalTooLarge
        }

        let data = try Data(contentsOf: context.journalURL, options: .mappedIfSafe)
        let journal: Journal
        do {
            journal = try PropertyListDecoder().decode(Journal.self, from: data)
        } catch {
            throw FileMoveTransactionSecurityError.invalidJournal
        }
        guard journal.schemaVersion == schemaVersion else {
            throw FileMoveTransactionSecurityError.invalidJournal
        }
        guard journal.allowedRootPaths == context.allowedRootPaths else {
            throw FileMoveTransactionSecurityError.rootsDoNotMatch
        }
        guard !journal.operations.isEmpty else {
            throw FileMoveTransactionSecurityError.invalidJournal
        }

        let operations = journal.operations.map {
            FileMoveOperation(
                sourceURL: $0.sourceURL.standardizedFileURL,
                destinationURL: $0.destinationURL.standardizedFileURL
            )
        }
        try validateSecurityBoundary(
            operations,
            context: context,
            fileManager: fileManager
        )

        let mover = moveItem ?? { sourceURL, destinationURL in
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
        var recoveryErrors: [String] = []

        for operation in operations.reversed() {
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

        try fileManager.removeItem(at: context.journalURL)
    }

    private static func prepareJournalDirectory(
        _ directoryURL: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            let values = try directoryURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true else {
                throw FileMoveTransactionSecurityError.symbolicLinkEndpoint
            }
            guard values.isDirectory == true else {
                throw FileMoveTransactionSecurityError.invalidJournal
            }
        } else {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
    }

    private static func validateSecurityBoundary(
        _ operations: [FileMoveOperation],
        context: FileMoveTransactionContext,
        fileManager: FileManager
    ) throws {
        guard operations.count <= maximumOperationCount else {
            throw FileMoveTransactionSecurityError.tooManyOperations
        }

        for operation in operations {
            guard operation.sourceURL.isFileURL,
                  operation.destinationURL.isFileURL
            else {
                throw FileMoveTransactionSecurityError.operationOutsideApprovedFolders
            }

            let sourcePath = canonicalPathResolvingExistingAncestor(for: operation.sourceURL)
            let destinationPath = canonicalPathResolvingExistingAncestor(
                for: operation.destinationURL
            )
            guard sourcePath != destinationPath,
                  isStrictDescendant(sourcePath, ofAny: context.allowedRootPaths),
                  isStrictDescendant(destinationPath, ofAny: context.allowedRootPaths)
            else {
                throw FileMoveTransactionSecurityError.operationOutsideApprovedFolders
            }

            try validateExistingEndpoint(operation.sourceURL, fileManager: fileManager)
            try validateExistingEndpoint(operation.destinationURL, fileManager: fileManager)
        }
    }

    private static func validateExistingEndpoint(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw FileMoveTransactionSecurityError.symbolicLinkEndpoint
        }
        guard values.isDirectory == true else {
            throw FileMoveTransactionSecurityError.nonDirectoryEndpoint
        }
    }

    private static func isStrictDescendant(_ path: String, ofAny roots: [String]) -> Bool {
        roots.contains { rootPath in
            path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
        }
    }

    fileprivate static func canonicalPathResolvingExistingAncestor(for url: URL) -> String {
        let standardizedURL = url.standardizedFileURL
        var unresolvedComponents: [String] = []
        var candidateURL = standardizedURL

        while !FileManager.default.fileExists(atPath: candidateURL.path) {
            let parentURL = candidateURL.deletingLastPathComponent()
            guard parentURL.path != candidateURL.path else {
                return standardizedURL.path
            }
            unresolvedComponents.append(candidateURL.lastPathComponent)
            candidateURL = parentURL
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(candidateURL.path, &pathBuffer) != nil else {
            return standardizedURL.path
        }

        return unresolvedComponents.reversed().reduce(String(cString: pathBuffer)) {
            URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent($1)
                .path
        }
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
}
