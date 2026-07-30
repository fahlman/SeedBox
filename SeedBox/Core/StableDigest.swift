import CryptoKit
import Foundation

enum StableDigest {
    static func sha256Hex(components: [String]) -> String {
        let data = Data(components.joined(separator: "\u{0}").utf8)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
