import SwiftUI

struct ModSetComparisonSheet: View {
    var comparison: ModSetComparison
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppStrings.ModSetComparison.title(comparison.modSet.name))
                .font(.title3)
                .fontWeight(.semibold)

            Text(AppStrings.ModSetComparison.summary(
                enableCount: comparison.enableCount,
                disableCount: comparison.disableCount
            ))
            .foregroundStyle(.secondary)

            if comparison.hasDifferences {
                differencesTable
            } else {
                ContentUnavailableView(
                    AppStrings.ModSetComparison.noChanges,
                    systemImage: "checkmark.circle"
                )
                .frame(minHeight: 180)
            }

            SheetCloseButton(close: close)
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 380)
    }

    private var differencesTable: some View {
        Table(comparison.differences) {
            TableColumn(AppStrings.ModSetComparison.changeColumn) { difference in
                Label(difference.change.displayText, systemImage: difference.change.systemImage)
                    .foregroundStyle(difference.change.foregroundStyle)
            }
            .width(min: 90, ideal: 110, max: 140)

            TableColumn(AppStrings.ModSetComparison.modColumn) { difference in
                Text(difference.mod.displayName)
            }

            TableColumn(AppStrings.ModSetComparison.versionColumn) { difference in
                Text(difference.mod.versionText)
            }
            .width(min: 90, ideal: 110, max: 140)

            TableColumn(AppStrings.ModSetComparison.typeColumn) { difference in
                Text(difference.mod.typeText)
            }
            .width(min: 90, ideal: 110, max: 140)
        }
        .frame(minHeight: 220, idealHeight: 300)
    }
}

private extension ModSetDifference.Change {
    var displayText: String {
        switch self {
        case .enable:
            return AppStrings.ModSetComparison.enable
        case .disable:
            return AppStrings.ModSetComparison.disable
        }
    }

    var systemImage: String {
        switch self {
        case .enable:
            return "checkmark.circle"
        case .disable:
            return "pause.circle"
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .enable:
            return .accentColor
        case .disable:
            return .secondary
        }
    }
}
