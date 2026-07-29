import Darwin
import Foundation

enum BoundedFileReadError: Error, Equatable, LocalizedError, Sendable {
    case unreadable
    case notRegularFile
    case exceedsLimit(maximumByteCount: Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "The file could not be read.")
        case .notRegularFile:
            String(localized: "The selected item is not a regular file.")
        case .exceedsLimit(let maximumByteCount):
            String(
                localized: "The file is larger than the \(maximumByteCount)-byte safety limit."
            )
        }
    }
}

enum BoundedFileReader {
    private static let chunkByteCount = 64 * 1_024

    static func readRegularFile(
        at url: URL,
        maximumByteCount: Int
    ) throws -> Data {
        guard maximumByteCount >= 0 else {
            throw BoundedFileReadError.exceedsLimit(maximumByteCount: 0)
        }

        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw BoundedFileReadError.unreadable
        }

        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? file.close()
        }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw BoundedFileReadError.unreadable
        }
        guard metadata.st_mode & UInt16(S_IFMT) == UInt16(S_IFREG) else {
            throw BoundedFileReadError.notRegularFile
        }
        guard metadata.st_size >= 0,
              UInt64(metadata.st_size) <= UInt64(maximumByteCount)
        else {
            throw BoundedFileReadError.exceedsLimit(
                maximumByteCount: maximumByteCount
            )
        }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))

        while true {
            let remainingByteCount = maximumByteCount - data.count
            let probeByteCount = remainingByteCount == .max
                ? remainingByteCount
                : remainingByteCount + 1
            let readByteCount = min(
                chunkByteCount,
                max(1, probeByteCount)
            )
            let chunk: Data
            do {
                chunk = try file.read(upToCount: readByteCount) ?? Data()
            } catch {
                throw BoundedFileReadError.unreadable
            }

            guard !chunk.isEmpty else {
                return data
            }
            guard chunk.count <= remainingByteCount else {
                throw BoundedFileReadError.exceedsLimit(
                    maximumByteCount: maximumByteCount
                )
            }
            data.append(chunk)
        }
    }
}
