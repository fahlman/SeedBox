import Foundation

enum ModVersionComparator {
    static func compare(_ version: String, to otherVersion: String) -> ComparisonResult {
        version.compare(
            otherVersion,
            options: [.caseInsensitive, .numeric],
            range: nil,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func version(
        _ version: String?,
        satisfiesMinimum minimumVersion: String?
    ) -> Bool {
        guard let minimumVersion = minimumVersion?.trimmedNonEmpty else {
            return true
        }

        guard let version = version?.trimmedNonEmpty else {
            return false
        }

        return compare(version, to: minimumVersion) != .orderedAscending
    }
}
