import SwiftUI

struct ActivitySheet: View {
    var auditTrail: AuditTrailState
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppStrings.Activity.title)
                .font(.title3)
                .fontWeight(.semibold)

            if let error = auditTrail.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Table(auditTrail.recentEntries.reversed()) {
                TableColumn(AppStrings.Activity.timeColumn) { entry in
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
                .width(min: 150, ideal: 170, max: 220)

                TableColumn(AppStrings.Activity.actionColumn) { entry in
                    Text(entry.action.displayText)
                }
                .width(min: 130, ideal: 160, max: 220)

                TableColumn(AppStrings.Activity.summaryColumn) { entry in
                    Text(entry.summary)
                        .lineLimit(2)
                }
            }
            .frame(minHeight: 320)

            Text(auditTrail.logPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            SheetCloseButton(close: close)
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 480)
    }
}

private extension AuditLogAction {
    var displayText: String {
        switch self {
        case .modsFolderSelected:
            return AppStrings.AuditActions.modsFolderSelected
        case .modsFolderCreated:
            return AppStrings.AuditActions.modsFolderCreated
        case .modsAdded:
            return AppStrings.AuditActions.modsAdded
        case .modsInstallSkipped:
            return AppStrings.AuditActions.modsInstallSkipped
        case .modsUpdated:
            return AppStrings.AuditActions.modsUpdated
        case .modEnabled:
            return AppStrings.AuditActions.modEnabled
        case .modDisabled:
            return AppStrings.AuditActions.modDisabled
        case .modDeleted:
            return AppStrings.AuditActions.modDeleted
        case .modRestored:
            return AppStrings.AuditActions.modRestored
        case .modMovedToTrash:
            return AppStrings.AuditActions.modMovedToTrash
        case .sourceFilesMovedToTrash:
            return AppStrings.AuditActions.sourceFilesMovedToTrash
        case .modSetCreated:
            return AppStrings.AuditActions.modSetCreated
        case .modSetRenamed:
            return AppStrings.AuditActions.modSetRenamed
        case .modSetApplied:
            return AppStrings.AuditActions.modSetApplied
        case .modSetDeleted:
            return AppStrings.AuditActions.modSetDeleted
        case .archivesPruned:
            return AppStrings.AuditActions.archivesPruned
        }
    }
}
