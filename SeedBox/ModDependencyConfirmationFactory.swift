import SwiftUI

struct ModDependencyConfirmationFactory {
    static func applying(
        set: ModSet,
        dependencyGraph: ModDependencyGraph
    ) -> DependencyConfirmation? {
        let issues = dependencyGraph.issues(applying: set)
        guard !issues.isEmpty else {
            return nil
        }

        return DependencyConfirmation(
            title: AppStrings.Alerts.unresolvedRequiredDependencies,
            message: modSetDependencyWarningMessage(set: set, issues: issues),
            confirmTitle: AppStrings.Alerts.applyAnyway,
            confirmRole: nil,
            action: .selectModSet(set.id)
        )
    }

    static func enabling(
        mod: ModInfo,
        dependencyGraph: ModDependencyGraph
    ) -> DependencyConfirmation? {
        let issues = dependencyGraph.requiredIssuesIfEnabled(mod)
        guard !issues.isEmpty else {
            return nil
        }

        let repairMods = dependencyGraph.disabledModsSatisfying(issues)
        let canRepairAllIssues = repairMods.count == issues.count
        return DependencyConfirmation(
            title: AppStrings.Alerts.missingRequiredDependencies,
            message: enableDependencyWarningMessage(mod: mod, issues: issues),
            confirmTitle: AppStrings.Alerts.enableAnyway,
            confirmRole: nil,
            action: .setMod(mod, enabled: true),
            repairTitle: canRepairAllIssues ? AppStrings.Alerts.enableRequiredDependencies : nil,
            repairRole: nil,
            repairAction: canRepairAllIssues ? .setMods(repairMods + [mod], enabled: true) : nil
        )
    }

    static func disabling(
        mod: ModInfo,
        dependencyGraph: ModDependencyGraph
    ) -> DependencyConfirmation? {
        let dependents = dependencyGraph.enabledDependentsIfDisabled(mod)
        guard !dependents.isEmpty else {
            return nil
        }

        return DependencyConfirmation(
            title: AppStrings.Alerts.requiredByEnabledMods,
            message: disableDependencyWarningMessage(mod: mod, dependents: dependents),
            confirmTitle: AppStrings.Alerts.disableAnyway,
            confirmRole: .destructive,
            action: .setMod(mod, enabled: false),
            repairTitle: AppStrings.Alerts.disableDependentMods,
            repairRole: .destructive,
            repairAction: .setMods(dependents + [mod], enabled: false)
        )
    }

    private static func enableDependencyWarningMessage(
        mod: ModInfo,
        issues: [ModDependencyResolution]
    ) -> String {
        AppStrings.Dependency.enableWarning(
            modName: mod.displayName,
            dependencySummary: AppStrings.Dependency.formattedList(issues.map(\.summaryText)),
            dependencyCount: issues.count
        )
    }

    private static func disableDependencyWarningMessage(
        mod: ModInfo,
        dependents: [ModInfo]
    ) -> String {
        AppStrings.Dependency.disableWarning(
            modName: mod.displayName,
            dependentSummary: AppStrings.Dependency.formattedList(dependents.map(\.displayName)),
            dependentCount: dependents.count
        )
    }

    private static func modSetDependencyWarningMessage(
        set: ModSet,
        issues: [ModDependencyIssue]
    ) -> String {
        if let issue = issues.first, issues.count == 1 {
            return AppStrings.Dependency.singleModSetIssue(
                setName: set.name,
                modName: issue.modName,
                dependencySummary: issue.dependencySummaryText
            )
        }

        let examples = issues
            .prefix(3)
            .map { issue in
                "\(issue.modName): \(issue.dependencySummaryText)"
            }
            .joined(separator: "\n")

        return AppStrings.Dependency.multipleModSetIssues(
            setName: set.name,
            issueCount: issues.count,
            examples: examples
        )
    }
}
