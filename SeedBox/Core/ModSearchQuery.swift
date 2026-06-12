import Foundation

struct ModSearchQuery: Sendable {
    private enum Field: String, Sendable {
        case state
        case mod
        case author
        case type
        case updates
        case version
        case id
        case folder
        case dependency
        case requires
        case requiredby
    }

    private struct Term: Sendable {
        var field: Field?
        var value: String
    }

    private var terms: [Term]

    init(_ rawValue: String) {
        terms = Self.parse(rawValue)
    }

    func matches(
        _ mod: ModInfo,
        in graph: ModDependencyGraph? = nil,
        hasAvailableUpdate: Bool = false
    ) -> Bool {
        guard !terms.isEmpty else {
            return true
        }

        return terms.allSatisfy { term in
            switch term.field {
            case .state:
                return mod.stateText.matchesSearchValue(term.value)
            case .mod:
                return [
                    mod.displayName,
                    mod.versionText,
                    mod.descriptionText ?? ""
                ].contains { $0.matchesSearchValue(term.value) }
            case .author:
                return mod.authorText.matchesSearchValue(term.value)
            case .type:
                return mod.typeText.matchesSearchValue(term.value)
            case .updates:
                if term.value.normalizedSearchText == "available" {
                    return hasAvailableUpdate
                }
                return [
                    mod.updateSourceText,
                    mod.updateKeysText ?? ""
                ].contains { $0.matchesSearchValue(term.value) }
            case .version:
                return mod.versionText.matchesSearchValue(term.value)
            case .id:
                return mod.manifest?.uniqueID?.matchesSearchValue(term.value) == true
            case .folder:
                return mod.folderName.matchesSearchValue(term.value)
            case .dependency:
                return matchesDependencyField(term.value, mod: mod, graph: graph)
            case .requires:
                return matchesRequiresField(term.value, mod: mod, graph: graph)
            case .requiredby:
                return graph?.dependents(of: mod).contains { dependent in
                    dependent.displayName.matchesSearchValue(term.value)
                        || dependent.manifest?.uniqueID?.matchesSearchValue(term.value) == true
                } ?? false
            case nil:
                return [
                    mod.stateText,
                    mod.displayName,
                    mod.versionText,
                    mod.authorText,
                    mod.typeText,
                    mod.updateSourceText,
                    mod.updateKeysText ?? "",
                    mod.folderName,
                    mod.manifest?.description ?? "",
                    mod.manifest?.uniqueID ?? "",
                    mod.manifest?.entryDll ?? "",
                    mod.manifest?.minimumApiVersion ?? ""
                ].contains { $0.matchesSearchValue(term.value) }
                    || (graph?.dependencySearchValues(for: mod).contains {
                        $0.matchesSearchValue(term.value)
                    } ?? false)
            }
        }
    }

    private func matchesDependencyField(
        _ value: String,
        mod: ModInfo,
        graph: ModDependencyGraph?
    ) -> Bool {
        let normalizedValue = value.normalizedSearchText
        let dependencyIssues = mod.missingRequiredDependencies + mod.missingOptionalDependencies

        switch normalizedValue {
        case "missing":
            return dependencyIssues.contains { $0.problem == .missing }
        case "disabled":
            return dependencyIssues.contains { $0.problem == .disabled }
        case "outdated", "old", "version":
            return dependencyIssues.contains { $0.problem == .versionTooOld }
        case "required":
            return mod.hasMissingRequiredDependencies
        case "optional":
            return mod.hasMissingOptionalDependencies
        case "ok", "healthy":
            return dependencyIssues.isEmpty
        default:
            return graph?.dependencySearchValues(for: mod).contains {
                $0.matchesSearchValue(value)
            } ?? false
        }
    }

    private func matchesRequiresField(
        _ value: String,
        mod: ModInfo,
        graph: ModDependencyGraph?
    ) -> Bool {
        let requirementValues = mod.dependencyRequirements.flatMap { requirement in
            [
                requirement.uniqueID,
                requirement.minimumVersion ?? ""
            ]
        }

        return requirementValues.contains { $0.matchesSearchValue(value) }
            || (graph?.dependencySearchValues(for: mod).contains {
                $0.matchesSearchValue(value)
            } ?? false)
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
