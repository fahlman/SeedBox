import Foundation

extension ModManagerService {
    func auditArchivesPruned(
        count: Int,
        summary: String,
        source: String? = nil,
        in state: inout ModManagerState
    ) {
        var details = [
            "pruned_count": "\(count)",
            "archive_retention_days": "\(state.archiveSettings.normalizedRetentionDays)"
        ]
        if let source {
            details["source"] = source
        }

        audit(
            .archivesPruned,
            summary: summary,
            subjects: [
                ModManagerAuditSubjects.archive(path: install(for: state).archivedModsDirectoryURL.path)
            ],
            details: details,
            in: &state
        )
    }

    func auditDeletedModSet(
        _ set: ModSet,
        wasSelected: Bool,
        details: [String: String] = [:],
        in state: inout ModManagerState
    ) {
        var mergedDetails = details
        mergedDetails["was_selected"] = wasSelected ? "true" : "false"

        audit(
            .modSetDeleted,
            summary: state.activityMessage,
            subjects: [auditSubjectForModSet(set)],
            details: mergedDetails,
            in: &state
        )
    }

    func audit(
        _ action: AuditLogAction,
        summary: String,
        subjects: [AuditLogSubject] = [],
        details: [String: String] = [:],
        in state: inout ModManagerState
    ) {
        auditRecorder.append(
            action,
            summary: summary,
            subjects: subjects,
            details: details,
            in: &state
        )
    }

    func auditSubjectForInstalledMod(_ url: URL) -> AuditLogSubject {
        ModManagerAuditSubjects.installedMod(url)
    }

    func auditSubjectForRestoredMod(_ result: RestoredModResult) -> AuditLogSubject {
        ModManagerAuditSubjects.restoredMod(result)
    }

    func auditSubjectForMod(
        _ mod: ModInfo,
        path: String? = nil
    ) -> AuditLogSubject {
        ModManagerAuditSubjects.mod(mod, path: path)
    }

    func auditSubjectForModSet(_ set: ModSet) -> AuditLogSubject {
        ModManagerAuditSubjects.modSet(set)
    }

    func auditSubjectForFolder(_ url: URL) -> AuditLogSubject {
        ModManagerAuditSubjects.folder(url)
    }

    func auditSubjectForSourceFile(_ url: URL) -> AuditLogSubject {
        ModManagerAuditSubjects.sourceFile(url)
    }
}
