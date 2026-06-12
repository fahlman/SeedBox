import Foundation

enum ModVersionComparator {
    static func compare(_ version: String, to otherVersion: String) -> ComparisonResult {
        guard let parsed = SemanticModVersion(version),
              let otherParsed = SemanticModVersion(otherVersion)
        else {
            return fallbackCompare(version, to: otherVersion)
        }

        return parsed.compare(to: otherParsed)
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

    private static func fallbackCompare(_ version: String, to otherVersion: String) -> ComparisonResult {
        version.compare(
            otherVersion,
            options: [.caseInsensitive, .numeric],
            range: nil,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

/// A SMAPI-style semantic version: numeric release components, an optional
/// prerelease tag after `-`, and ignored build metadata after `+`.
private struct SemanticModVersion {
    var releaseComponents: [Int]
    var prereleaseIdentifiers: [String]

    init?(_ rawValue: String) {
        var remainder = Substring(rawValue.trimmingCharacters(in: .whitespaces))
        guard !remainder.isEmpty else {
            return nil
        }

        if let metadataIndex = remainder.firstIndex(of: "+") {
            remainder = remainder[..<metadataIndex]
        }

        let prerelease: Substring?
        if let prereleaseIndex = remainder.firstIndex(of: "-") {
            prerelease = remainder[remainder.index(after: prereleaseIndex)...]
            remainder = remainder[..<prereleaseIndex]
        } else {
            prerelease = nil
        }

        let releaseComponents = remainder.split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) }
        guard !releaseComponents.isEmpty, releaseComponents.allSatisfy({ $0 != nil }) else {
            return nil
        }

        self.releaseComponents = releaseComponents.compactMap { $0 }
        prereleaseIdentifiers = prerelease?.split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init) ?? []
    }

    func compare(to other: SemanticModVersion) -> ComparisonResult {
        let componentCount = max(releaseComponents.count, other.releaseComponents.count)
        for index in 0..<componentCount {
            let component = index < releaseComponents.count ? releaseComponents[index] : 0
            let otherComponent = index < other.releaseComponents.count ? other.releaseComponents[index] : 0
            if component != otherComponent {
                return component < otherComponent ? .orderedAscending : .orderedDescending
            }
        }

        switch (prereleaseIdentifiers.isEmpty, other.prereleaseIdentifiers.isEmpty) {
        case (true, true):
            return .orderedSame
        case (true, false):
            return .orderedDescending
        case (false, true):
            return .orderedAscending
        case (false, false):
            return comparePrereleaseIdentifiers(to: other)
        }
    }

    private func comparePrereleaseIdentifiers(to other: SemanticModVersion) -> ComparisonResult {
        for (identifier, otherIdentifier) in zip(prereleaseIdentifiers, other.prereleaseIdentifiers) {
            let result = Self.compareIdentifier(identifier, to: otherIdentifier)
            if result != .orderedSame {
                return result
            }
        }

        if prereleaseIdentifiers.count != other.prereleaseIdentifiers.count {
            return prereleaseIdentifiers.count < other.prereleaseIdentifiers.count
                ? .orderedAscending
                : .orderedDescending
        }

        return .orderedSame
    }

    private static func compareIdentifier(_ identifier: String, to otherIdentifier: String) -> ComparisonResult {
        switch (Int(identifier), Int(otherIdentifier)) {
        case (.some(let number), .some(let otherNumber)):
            guard number != otherNumber else {
                return .orderedSame
            }
            return number < otherNumber ? .orderedAscending : .orderedDescending
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case (.none, .none):
            return identifier.compare(
                otherIdentifier,
                options: [.caseInsensitive],
                range: nil,
                locale: Locale(identifier: "en_US_POSIX")
            )
        }
    }
}
