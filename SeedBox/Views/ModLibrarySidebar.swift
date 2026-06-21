import SwiftUI

struct ModLibrarySidebar: View {
    var presentationState: ModManagerPresentationState
    @Binding var selectedItemID: String
    var selectItem: (String) -> Void

    var body: some View {
        List(selection: selectedItemBinding) {
            Section(AppStrings.Library.smartModSets) {
                ForEach(presentationState.builtInSmartModSetItems) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .badge(item.count)
                        .tag(item.id)
                }

                ForEach(presentationState.userSmartModSetItems) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .badge(item.count)
                        .tag(item.id)
                }
            }

            Section(AppStrings.Help.modSetsTitle) {
                ForEach(presentationState.modSetItems) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .badge(item.count)
                        .tag(item.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppStrings.Library.library)
        .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 280)
    }

    private var selectedItemBinding: Binding<String?> {
        Binding(
            get: {
                selectedItemID
            },
            set: { newItemID in
                guard let newItemID else {
                    return
                }
                selectItem(newItemID)
            }
        )
    }

}
