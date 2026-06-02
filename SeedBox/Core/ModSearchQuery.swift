import Foundation

struct ModSearchQuery: Sendable {
    private enum Field: String, Sendable {
        case state
        case mod
        case author
        case type
    }

    private struct Term: Sendable {
        var field: Field?
        var value: String
    }

    private var terms: [Term]

    init(_ rawValue: String) {
        terms = Self.parse(rawValue)
    }

    func matches(_ mod: ModInfo) -> Bool {
        guard !terms.isEmpty else {
            return true
        }

        return terms.allSatisfy { term in
            switch term.field {
            case .state:
                return mod.stateText.matchesSearchValue(term.value)
            case .mod:
                return "\(mod.displayName) \(mod.versionText)".matchesSearchValue(term.value)
            case .author:
                return mod.authorText.matchesSearchValue(term.value)
            case .type:
                return mod.typeText.matchesSearchValue(term.value)
            case nil:
                return [
                    mod.stateText,
                    mod.displayName,
                    mod.versionText,
                    mod.authorText,
                    mod.typeText,
                    mod.manifest?.description ?? "",
                    mod.manifest?.uniqueID ?? ""
                ].contains { $0.matchesSearchValue(term.value) }
            }
        }
    }

    private static func parse(_ rawValue: String) -> [Term] {
        tokens(in: rawValue).compactMap { token in
            guard let splitIndex = token.firstIndex(of: ":") else {
                return Term(field: nil, value: token)
            }

            let fieldName = String(token[..<splitIndex]).lowercased()
            let valueStartIndex = token.index(after: splitIndex)
            let value = String(token[valueStartIndex...])
            guard let field = Field(rawValue: fieldName), !value.isEmpty else {
                return Term(field: nil, value: token)
            }

            return Term(field: field, value: value)
        }
    }

    private static func tokens(in rawValue: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""
        var isInsideQuotes = false

        for character in rawValue {
            if character == "\"" {
                isInsideQuotes.toggle()
                continue
            }

            if character.isWhitespace && !isInsideQuotes {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                continue
            }

            currentToken.append(character)
        }

        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        return tokens
    }
}
