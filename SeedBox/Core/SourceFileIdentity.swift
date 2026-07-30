import Darwin
import Foundation

struct SourceFileIdentity: Codable, Equatable, Sendable {
    private var device: UInt64
    private var inode: UInt64
    private var fileType: UInt16
    private var birthSeconds: Int64
    private var birthNanoseconds: Int64

    init?(url: URL) {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else {
            return nil
        }

        let fileType = metadata.st_mode & UInt16(S_IFMT)
        guard fileType == UInt16(S_IFREG) || fileType == UInt16(S_IFDIR) else {
            return nil
        }

        device = UInt64(bitPattern: Int64(metadata.st_dev))
        inode = metadata.st_ino
        self.fileType = fileType
        birthSeconds = Int64(metadata.st_birthtimespec.tv_sec)
        birthNanoseconds = Int64(metadata.st_birthtimespec.tv_nsec)
    }

    func matchesFile(at url: URL) -> Bool {
        SourceFileIdentity(url: url) == self
    }

    func matchesFileType(at url: URL) -> Bool {
        SourceFileIdentity(url: url)?.fileType == fileType
    }
}

struct SourceCleanupCandidate: Equatable, Sendable {
    var url: URL
    var identity: SourceFileIdentity
}
