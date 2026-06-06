import Foundation

struct ModManagerAuditRecorder: Sendable {
    var logURL: URL

    func reloadTrail(in state: inout ModManagerState) {
        state.auditTrail.logPath = logURL.path

        do {
            state.auditTrail.recentEntries = try AuditLogStore.loadEntries(
                from: logURL,
                limit: AuditLogStore.recentEntryLimit
            )
            state.auditTrail.lastErrorMessage = nil
        } catch {
            state.auditTrail.lastErrorMessage = error.localizedDescription
        }
    }

    func append(
        _ action: AuditLogAction,
        summary: String,
        subjects: [AuditLogSubject] = [],
        details: [String: String] = [:],
        in state: inout ModManagerState
    ) {
        let entry = AuditLogEntry(
            action: action,
            summary: summary,
            modsDirectoryPath: state.modsDirectoryPath,
            selectedModSetID: state.selectedModSetID,
            selectedModSetName: state.modSetSelection.selectedSet?.name,
            appliedModSetID: state.appliedModSetID,
            subjects: subjects,
            details: details
        )

        do {
            try AuditLogStore.append(entry, to: logURL)
            reloadTrail(in: &state)
            state.activityMessage = ""
        } catch {
            state.auditTrail.lastErrorMessage = error.localizedDescription
        }
    }
}

enum ModManagerAuditSubjects {
    static func installedMod(_ url: URL) -> AuditLogSubject {
        AuditLogSubject(
            kind: .mod,
            id: nil,
            name: url.lastPathComponent.trimmingPrefix(Character(".")),
            path: url.path
        )
    }

    static func restoredMod(_ result: RestoredModResult) -> AuditLogSubject {
        AuditLogSubject(
            kind: .mod,
            id: nil,
            name: result.displayName,
            path: result.destinationURL.path
        )
    }

    static func mod(_ mod: ModInfo, path: String? = nil) -> AuditLogSubject {
        AuditLogSubject(
            kind: .mod,
            id: mod.id,
            name: mod.displayName,
            path: path ?? mod.url.path
        )
    }

    static func modSet(_ set: ModSet) -> AuditLogSubject {
        AuditLogSubject(
            kind: .modSet,
            id: set.id,
            name: set.name,
            path: nil
        )
    }

    static func folder(_ url: URL) -> AuditLogSubject {
        AuditLogSubject(
            kind: .modsFolder,
            id: nil,
            name: url.lastPathComponent,
            path: url.path
        )
    }

    static func sourceFile(_ url: URL) -> AuditLogSubject {
        AuditLogSubject(
            kind: .sourceFile,
            id: nil,
            name: url.lastPathComponent,
            path: url.path
        )
    }

    static func archive(path: String) -> AuditLogSubject {
        AuditLogSubject(
            kind: .archive,
            id: nil,
            name: AppStrings.ModInspector.archiveSection,
            path: path
        )
    }
}
