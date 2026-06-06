import SwiftUI

struct SourceCleanupOfferSheet: View {
    var offer: SourceCleanupOffer
    @Binding var remembersChoice: Bool
    var keepFiles: () -> Void
    var moveToTrash: () -> Void
    var dismissNotice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !offer.isNotificationOnly {
                Toggle(AppStrings.SourceCleanup.rememberChoice, isOn: $remembersChoice)
            }

            HStack {
                Spacer()

                if offer.isNotificationOnly {
                    Button(AppStrings.SourceCleanup.ok) {
                        dismissNotice()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(AppStrings.SourceCleanup.keepFiles, role: .cancel) {
                        keepFiles()
                    }

                    Button(AppStrings.SourceCleanup.moveToTrash, role: .destructive) {
                        moveToTrash()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    private var title: String {
        offer.isNotificationOnly
            ? AppStrings.SourceCleanup.modsAddedTitle
            : AppStrings.SourceCleanup.moveOriginalFilesToTrashTitle
    }

    private var message: String {
        if offer.isNotificationOnly {
            return [offer.importSummary, offer.cleanupSummary]
                .compactMap { $0?.trimmedNonEmpty }
                .joined(separator: "\n\n")
        }

        return "\(offer.importSummary)\n\n\(AppStrings.SourceCleanup.moveSelectedItemsQuestion(count: offer.sourceCount))"
    }
}
