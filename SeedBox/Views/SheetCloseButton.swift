import SwiftUI

struct SheetCloseButton: View {
    var close: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(AppStrings.ModSetComparison.close) {
                close()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
