import SwiftUI

struct ModNameCell: View {
    var mod: ModInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(mod.displayName)
                    .font(.headline)
                    .lineLimit(1)

                Text(mod.versionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let description = mod.descriptionText {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(description)
            }

            if let missingDependenciesText = mod.missingRequiredDependenciesText {
                Label(missingDependenciesText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
    }
}
