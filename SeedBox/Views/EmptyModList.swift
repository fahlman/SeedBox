import SwiftUI

struct EmptyModList: View {
    @ObservedObject var viewModel: ModManagerViewModel
    var addMods: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)

            Text("No mods in \(viewModel.modFolderName)")
                .font(.title3.weight(.semibold))

            Text("Add an unzipped mod folder to install it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                addMods()
            } label: {
                Label("Add Mods", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.state.readiness.canManageMods)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
