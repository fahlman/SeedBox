import SwiftUI

struct ModImportPreviewSheet: View {
    var preview: ModImportPreview
    var cancel: () -> Void
    var install: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppStrings.ImportPreview.title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(AppStrings.ImportPreview.summary(
                itemCount: preview.items.count,
                installableCount: preview.installableItems.count
            ))
            .foregroundStyle(.secondary)

            Table(preview.items) {
                TableColumn(AppStrings.ImportPreview.actionColumn) { item in
                    Label(item.action.displayText, systemImage: item.action.systemImage)
                        .foregroundStyle(item.action.foregroundStyle)
                        .lineLimit(1)
                }
                .width(min: 110, ideal: 130, max: 170)

                TableColumn(AppStrings.ImportPreview.modColumn) { item in
                    Text(item.displayName)
                        .lineLimit(1)
                }

                TableColumn(AppStrings.ImportPreview.selectedVersionColumn) { item in
                    Text(item.selectedVersionText)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 110, max: 150)

                TableColumn(AppStrings.ImportPreview.installedVersionColumn) { item in
                    Text(item.existingVersionText)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 110, max: 150)

                TableColumn(AppStrings.ImportPreview.typeColumn) { item in
                    Text(item.typeText)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 110, max: 140)

                TableColumn(AppStrings.ImportPreview.detailsColumn) { item in
                    Text(item.detailText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 160, ideal: 220)
            }
            .frame(minHeight: 220, idealHeight: 280)

            Text(AppStrings.ImportPreview.restoreNote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button(AppStrings.ImportPreview.cancel, role: .cancel) {
                    cancel()
                }

                Button(AppStrings.ImportPreview.installAction) {
                    install()
                }
                .disabled(!preview.canInstall)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 430)
    }
}

private extension ModImportPreviewAction {
    var displayText: String {
        switch self {
        case .install:
            return AppStrings.ImportPreview.install
        case .update:
            return AppStrings.ImportPreview.update
        case .reinstall:
            return AppStrings.ImportPreview.reinstall
        case .downgrade:
            return AppStrings.ImportPreview.downgrade
        case .replace:
            return AppStrings.ImportPreview.replace
        case .alreadyInstalled:
            return AppStrings.ImportPreview.skip
        case .duplicateInSelection:
            return AppStrings.ImportPreview.duplicate
        }
    }

    var systemImage: String {
        switch self {
        case .install:
            return "plus.circle"
        case .update:
            return "arrow.up.circle"
        case .reinstall:
            return "arrow.clockwise.circle"
        case .downgrade:
            return "arrow.down.circle"
        case .replace:
            return "arrow.triangle.2.circlepath.circle"
        case .alreadyInstalled:
            return "checkmark.circle"
        case .duplicateInSelection:
            return "exclamationmark.triangle"
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .install, .update:
            return .accentColor
        case .downgrade, .duplicateInSelection:
            return .orange
        case .reinstall, .replace, .alreadyInstalled:
            return .secondary
        }
    }
}

private extension ModImportPreviewItem {
    var detailText: String {
        switch action {
        case .install:
            return AppStrings.ImportPreview.willInstall(destinationFolderName)
        case .update:
            return AppStrings.ImportPreview.willUpdate(existingFolderName ?? destinationFolderName)
        case .reinstall:
            return AppStrings.ImportPreview.willReinstall(existingFolderName ?? destinationFolderName)
        case .downgrade:
            return AppStrings.ImportPreview.willDowngrade(existingFolderName ?? destinationFolderName)
        case .replace:
            return AppStrings.ImportPreview.willReplace(existingFolderName ?? destinationFolderName)
        case .alreadyInstalled:
            return AppStrings.ImportPreview.alreadyInstalled(existingFolderName ?? destinationFolderName)
        case .duplicateInSelection:
            return AppStrings.ImportPreview.duplicateSelection
        }
    }
}
