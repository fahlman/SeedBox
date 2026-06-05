import Foundation

enum ModDependencyRequirementKind: Equatable, Sendable {
    case contentPackFor
    case requiredDependency
    case optionalDependency

    var isRequired: Bool {
        switch self {
        case .contentPackFor, .requiredDependency:
            return true
        case .optionalDependency:
            return false
        }
    }
}

struct ModDependencyRequirement: Equatable, Sendable {
    var uniqueID: String
    var minimumVersion: String?
    var kind: ModDependencyRequirementKind

    var normalizedUniqueID: String {
        uniqueID.normalizedDependencyID
    }
}

enum ModDependencyProblem: Equatable, Sendable {
    case missing
    case disabled
    case versionTooOld
}

struct ModDependencyResolution: Equatable, Sendable {
    var requirement: ModDependencyRequirement
    var problem: ModDependencyProblem
    var matchedModID: String?
    var matchedModName: String?
    var matchedModVersion: String?

    var displayName: String {
        matchedModName ?? requirement.uniqueID
    }

    var searchText: String {
        [
            requirement.uniqueID,
            requirement.minimumVersion ?? "",
            matchedModName ?? "",
            matchedModVersion ?? "",
            problem.searchText
        ]
        .joined(separator: " ")
    }

    var summaryText: String {
        switch problem {
        case .missing:
            if let minimumVersion = requirement.minimumVersion {
                return AppStrings.Dependency.missing(displayName: displayName, minimumVersion: minimumVersion)
            }
            return AppStrings.Dependency.missing(displayName: displayName)
        case .disabled:
            if let minimumVersion = requirement.minimumVersion {
                return AppStrings.Dependency.disabled(displayName: displayName, minimumVersion: minimumVersion)
            }
            return AppStrings.Dependency.disabled(displayName: displayName)
        case .versionTooOld:
            guard let minimumVersion = requirement.minimumVersion else {
                return AppStrings.Dependency.tooOld(displayName: displayName)
            }
            let installedVersion = matchedModVersion ?? AppStrings.Mods.unknownVersion
            return AppStrings.Dependency.tooOld(
                displayName: displayName,
                installedVersion: installedVersion,
                minimumVersion: minimumVersion
            )
        }
    }
}

struct ModDependencyIssue: Equatable, Sendable {
    var modName: String
    var unsatisfiedRequirements: [ModDependencyResolution]

    var missingRequiredDependencyIDs: [String] {
        unsatisfiedRequirements.map(\.requirement.uniqueID)
    }

    var dependencySummaryText: String {
        unsatisfiedRequirements.map(\.summaryText).joined(separator: ", ")
    }
}

struct ModDependencyGraph: Sendable {
    private var mods: [ModInfo]
    private var modsByUniqueID: [String: ModInfo]

    init(mods: [ModInfo]) {
        self.mods = mods

        var modsByUniqueID: [String: ModInfo] = [:]
        for mod in mods {
            guard let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID,
                  modsByUniqueID[uniqueID] == nil
            else {
                continue
            }

            modsByUniqueID[uniqueID] = mod
        }
        self.modsByUniqueID = modsByUniqueID
    }

    func resolvedMods() -> [ModInfo] {
        let enabledModIDs = Set(mods.filter(\.isEnabled).map(\.id))

        return mods.map { mod in
            var resolvedMod = mod
            guard mod.isEnabled else {
                resolvedMod.missingRequiredDependencies = []
                resolvedMod.missingOptionalDependencies = []
                return resolvedMod
            }

            resolvedMod.missingRequiredDependencies = unsatisfiedRequirements(
                mod.requiredDependencyRequirements,
                for: mod,
                enabledModIDs: enabledModIDs
            )
            resolvedMod.missingOptionalDependencies = unsatisfiedRequirements(
                mod.optionalDependencyRequirements,
                for: mod,
                enabledModIDs: enabledModIDs
            )
            return resolvedMod
        }
    }

    func requiredIssuesIfEnabled(_ mod: ModInfo) -> [ModDependencyResolution] {
        var enabledModIDs = Set(mods.filter(\.isEnabled).map(\.id))
        enabledModIDs.insert(mod.id)
        return unsatisfiedRequirements(
            mod.requiredDependencyRequirements,
            for: mod,
            enabledModIDs: enabledModIDs
        )
    }

    func enabledDependentsIfDisabled(_ mod: ModInfo) -> [ModInfo] {
        dependents(of: mod).filter(\.isEnabled)
    }

    func dependents(of mod: ModInfo) -> [ModInfo] {
        guard let uniqueID = mod.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID else {
            return []
        }

        return mods
            .filter { candidate in
                candidate.id != mod.id
                    && candidate.requiredDependencyRequirements.contains { requirement in
                        requirement.normalizedUniqueID == uniqueID
                    }
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func issues(applying set: ModSet) -> [ModDependencyIssue] {
        let enabledModIDs = Set(mods.filter { isEnabled($0, applying: set) }.map(\.id))

        return mods
            .filter { isEnabled($0, applying: set) }
            .compactMap { mod in
                let issues = unsatisfiedRequirements(
                    mod.requiredDependencyRequirements,
                    for: mod,
                    enabledModIDs: enabledModIDs
                )
                guard !issues.isEmpty else {
                    return nil
                }

                return ModDependencyIssue(
                    modName: mod.displayName,
                    unsatisfiedRequirements: issues
                )
            }
            .sorted { lhs, rhs in
                lhs.modName.localizedCaseInsensitiveCompare(rhs.modName) == .orderedAscending
            }
    }

    func disabledModsSatisfying(_ issues: [ModDependencyResolution]) -> [ModInfo] {
        let modIDs = Set(
            issues.compactMap { issue in
                issue.problem == .disabled ? issue.matchedModID : nil
            }
        )

        return mods
            .filter { modIDs.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    func dependencySearchValues(for mod: ModInfo) -> [String] {
        let requirements = mod.dependencyRequirements.flatMap { requirement -> [String] in
            var values = [
                requirement.uniqueID,
                dependencyDisplayName(for: requirement)
            ]
            if let minimumVersion = requirement.minimumVersion {
                values.append(minimumVersion)
            }
            return values
        }
        let issues = (mod.missingRequiredDependencies + mod.missingOptionalDependencies).flatMap { issue in
            [
                issue.displayName,
                issue.requirement.uniqueID,
                issue.summaryText,
                issue.problem.searchText
            ]
        }

        return requirements + issues
    }

    private func dependencyDisplayName(for requirement: ModDependencyRequirement) -> String {
        modsByUniqueID[requirement.normalizedUniqueID]?.displayName ?? requirement.uniqueID
    }

    private func unsatisfiedRequirements(
        _ requirements: [ModDependencyRequirement],
        for mod: ModInfo? = nil,
        enabledModIDs: Set<String>
    ) -> [ModDependencyResolution] {
        let ownUniqueID = mod?.manifest?.uniqueID?.trimmedNonEmpty?.normalizedDependencyID

        return requirements.compactMap { requirement in
            let normalizedID = requirement.normalizedUniqueID
            guard !normalizedID.isEmpty, normalizedID != ownUniqueID else {
                return nil
            }

            guard let installedMod = modsByUniqueID[normalizedID] else {
                return ModDependencyResolution(
                    requirement: requirement,
                    problem: .missing,
                    matchedModID: nil,
                    matchedModName: nil,
                    matchedModVersion: nil
                )
            }

            let installedVersion = installedMod.manifest?.version?.trimmedNonEmpty
            guard ModVersionComparator.version(
                installedVersion,
                satisfiesMinimum: requirement.minimumVersion
            ) else {
                return ModDependencyResolution(
                    requirement: requirement,
                    problem: .versionTooOld,
                    matchedModID: installedMod.id,
                    matchedModName: installedMod.displayName,
                    matchedModVersion: installedVersion
                )
            }

            guard enabledModIDs.contains(installedMod.id) else {
                return ModDependencyResolution(
                    requirement: requirement,
                    problem: .disabled,
                    matchedModID: installedMod.id,
                    matchedModName: installedMod.displayName,
                    matchedModVersion: installedVersion
                )
            }

            return nil
        }
    }

    private func isEnabled(_ mod: ModInfo, applying set: ModSet) -> Bool {
        !set.disabledFolderTokens.contains(mod.enabledFolderName.normalizedFolderToken)
    }
}

private extension ModDependencyProblem {
    var searchText: String {
        switch self {
        case .missing:
            return "missing"
        case .disabled:
            return "disabled"
        case .versionTooOld:
            return "outdated old version too old"
        }
    }
}
