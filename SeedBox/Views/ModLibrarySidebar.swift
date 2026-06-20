import SwiftUI

struct ModLibrarySidebar: View {
    var presentationState: ModManagerPresentationState
    @Binding var selectedItemID: String
    var selectItem: (String) -> Void

    var body: some View {
        List(selection: selectedItemBinding) {
            Section(AppStrings.Library.smartModSets) {
                ForEach(SmartModSetDefinition.builtIn) { definition in
                    Label(definition.title, systemImage: definition.systemImage)
                        .badge(ModFilterEngine.count(for: definition.smartSet, in: presentationState.state))
                        .tag(ModLibrarySelection.smartID(definition.smartSet))
                }
            }

            Section(AppStrings.Help.modSetsTitle) {
                ForEach(presentationState.modSetSelection.sets) { set in
                    Label(set.name, systemImage: set.isUserEditable ? "folder" : "folder.badge.gearshape")
                        .badge(modCount(for: set))
                        .tag(ModLibrarySelection.modSetID(set.id))
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

    private func modCount(for set: ModSet) -> Int {
        let resolvedSet = ModSetResolver.resolve(set)
        return presentationState.state.mods.filter { mod in
            resolvedSet.isEnabled(mod)
        }.count
    }
}
