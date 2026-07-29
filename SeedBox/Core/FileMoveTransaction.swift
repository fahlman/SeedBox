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
    case fileIdentityChanged

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
        case .fileIdentityChanged:
            "Seed Box stopped because a mod folder changed during the file operation."
        }
    }
}

enum FileMoveTransaction {
    private static let schemaVersion = 3
    private static let maximumJournalByteCount = 4 * 1024 * 1024
    private static let maximumOperationCount = 10_000

    private struct Journal: Codable {
        var schemaVersion: Int
        var allowedRootPaths: [String]
        var operations: [JournalOperation]
    }

    private struct JournalOperation: Codable {
        var operation: FileMoveOperation
        var sourceIdentity: SourceFileIdentity
        var preservesFileIdentity: Bool
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
        let journalOperations = try operations.map { operation in
            guard let sourceIdentity = SourceFileIdentity(url: operation.sourceURL) else {
                throw FileMoveTransactionSecurityError.fileIdentityChanged
            }
            return JournalOperation(
                operation: operation,
                sourceIdentity: sourceIdentity,
                preservesFileIdentity: movePreservesFileIdentity(operation)
            )
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let journalData = try encoder.encode(
            Journal(
                schemaVersion: schemaVersion,
                allowedRootPaths: context.allowedRootPaths,
                operations: journalOperations
            )
        )
        guard journalData.count <= maximumJournalByteCount else {
            throw FileMoveTransactionSecurityError.journalTooLarge
        }
        try journalData.write(to: context.journalURL, options: .atomic)

        let mover = moveItem ?? { sourceURL, destinationURL in
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }
        var completedOperations: [JournalOperation] = []

        do {
            for journalOperation in journalOperations {
                let operation = journalOperation.operation
                guard journalOperation.sourceIdentity.matchesFile(
                    at: operation.sourceURL
                ) else {
                    throw FileMoveTransactionSecurityError.fileIdentityChanged
                }
                try mover(operation.sourceURL, operation.destinationURL)
                completedOperations.append(journalOperation)
                try verifyCompletedMove(journalOperation)
            }
        } catch {
            let rollbackErrors = rollback(
                completedOperations,
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
        guard values.fileSize ?? 0 <= maximumJournalByteCount else {
            throw FileMoveTransactionSecurityError.journalTooLarge
        }

        let data: Data
        do {
            data = try BoundedFileReader.readRegularFile(
                at: context.journalURL,
                maximumByteCount: maximumJournalByteCount
            )
        } catch BoundedFileReadError.exceedsLimit {
            throw FileMoveTransactionSecurityError.journalTooLarge
        } catch {
            throw FileMoveTransactionSecurityError.invalidJournal
        }
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
                sourceURL: $0.operation.sourceURL.standardizedFileURL,
                destinationURL: $0.operation.destinationURL.standardizedFileURL
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

        let normalizedJournalOperations = zip(journal.operations, operations).map {
            JournalOperation(
                operation: $1,
                sourceIdentity: $0.sourceIdentity,
                preservesFileIdentity: $0.preservesFileIdentity
            )
        }
        for journalOperation in normalizedJournalOperations.reversed() {
            let operation = journalOperation.operation
            let sourceExists = fileSystemEntryExists(at: operation.sourceURL)
            let destinationExists = fileSystemEntryExists(at: operation.destinationURL)

            switch (sourceExists, destinationExists) {
            case (true, false):
                guard journalOperation.sourceIdentity.matchesFile(
                    at: operation.sourceURL
                ) else {
                    recoveryErrors.append(
                        FileMoveTransactionSecurityError.fileIdentityChanged
                            .localizedDescription
                    )
                    continue
                }
                continue
            case (false, true):
                do {
                    guard matchesMovedEndpoint(
                        journalOperation,
                        at: operation.destinationURL
                    ) else {
                        throw FileMoveTransactionSecurityError.fileIdentityChanged
                    }
                    try mover(operation.destinationURL, operation.sourceURL)
                    guard matchesMovedEndpoint(
                        journalOperation,
                        at: operation.sourceURL
                    ),
                    !fileSystemEntryExists(at: operation.destinationURL)
                    else {
                        throw FileMoveTransactionSecurityError.fileIdentityChanged
                    }
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

        let resolvedPath = String(
            decoding: pathBuffer
                .prefix { $0 != 0 }
                .map(UInt8.init(bitPattern:)),
            as: UTF8.self
        )
        return unresolvedComponents.reversed().reduce(resolvedPath) {
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
        _ completedOperations: [JournalOperation],
        moveItem: (URL, URL) throws -> Void
    ) -> [String] {
        var errors: [String] = []
        for journalOperation in completedOperations.reversed() {
            let operation = journalOperation.operation
            do {
                guard !fileSystemEntryExists(at: operation.sourceURL),
                      matchesMovedEndpoint(
                          journalOperation,
                          at: operation.destinationURL
                      )
                else {
                    throw FileMoveTransactionSecurityError.fileIdentityChanged
                }
                try moveItem(operation.destinationURL, operation.sourceURL)
                guard matchesMovedEndpoint(
                    journalOperation,
                    at: operation.sourceURL
                ),
                !fileSystemEntryExists(at: operation.destinationURL)
                else {
                    throw FileMoveTransactionSecurityError.fileIdentityChanged
                }
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

    private static func verifyCompletedMove(
        _ journalOperation: JournalOperation
    ) throws {
        guard !fileSystemEntryExists(at: journalOperation.operation.sourceURL),
              matchesMovedEndpoint(
                  journalOperation,
                  at: journalOperation.operation.destinationURL
              )
        else {
            throw FileMoveTransactionSecurityError.fileIdentityChanged
        }
    }

    private static func matchesMovedEndpoint(
        _ journalOperation: JournalOperation,
        at url: URL
    ) -> Bool {
        if journalOperation.preservesFileIdentity {
            return journalOperation.sourceIdentity.matchesFile(at: url)
        }
        return journalOperation.sourceIdentity.matchesFileType(at: url)
    }

    private static func movePreservesFileIdentity(
        _ operation: FileMoveOperation
    ) -> Bool {
        let sourceVolume = try? operation.sourceURL.resourceValues(
            forKeys: [.volumeIdentifierKey]
        ).volumeIdentifier
        let destinationVolume = try? operation.destinationURL
            .deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeIdentifierKey])
            .volumeIdentifier
        guard let sourceVolume, let destinationVolume else {
            return false
        }
        return sourceVolume.isEqual(destinationVolume)
    }

    private static func fileSystemEntryExists(at url: URL) -> Bool {
        var metadata = stat()
        return lstat(url.path, &metadata) == 0
    }
}
