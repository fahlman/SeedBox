import SwiftUI

struct EmptyModList: View {
    @ObservedObject var viewModel: ModManagerViewModel
    var addMods: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text(AppStrings.EmptyState.noMods(in: viewModel.modFolderName))
                .font(.title3.weight(.semibold))

            Text(AppStrings.EmptyState.addModsPrompt)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                addMods()
            } label: {
                Label("Add Mods", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.state.readiness.canManageMods)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
