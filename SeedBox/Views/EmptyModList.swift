import SwiftUI

struct EmptyModList: View {
    var canManageMods: Bool
    var modFolderName: String
    var addMods: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text(AppStrings.EmptyState.noMods(in: modFolderName))
                .font(.title3.weight(.semibold))

            Text(AppStrings.EmptyState.addModsPrompt)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                addMods()
            } label: {
                Label(AppStrings.Toolbar.addMods, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canManageMods)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
