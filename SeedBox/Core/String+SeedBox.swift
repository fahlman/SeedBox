import Foundation

extension String {
    var normalizedFolderToken: String {
        trimmingPrefix(Character(".")).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedDependencyID: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedSearchText: String {
        lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    var compactSearchText: String {
        normalizedSearchText.replacingOccurrences(of: " ", with: "")
    }

    func matchesSearchValue(_ value: String) -> Bool {
        let normalizedValue = value.normalizedSearchText
        guard !normalizedValue.isEmpty else {
            return true
        }

        return normalizedSearchText.contains(normalizedValue)
            || compactSearchText.contains(value.compactSearchText)
    }

    func trimmingPrefix(_ prefix: Character) -> String {
        var value = self
        while value.first == prefix {
            value.removeFirst()
        }
        return value
    }
}
