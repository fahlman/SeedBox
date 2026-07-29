import Foundation
import Synchronization

/// Owns the temporary files extracted while preparing an import preview.
///
/// The preview can be handed to the installer exactly once. Until then, this
/// session removes its temporary files when it is discarded or released.
final class ModImportPreviewSession: Identifiable, @unchecked Sendable {
    let preview: ModImportPreview

    private let ownedPreview: Mutex<ModImportPreview?>

    init(preview: ModImportPreview) {
        self.preview = preview
        ownedPreview = Mutex(preview)
    }

    var id: UUID {
        preview.id
    }

    /// Transfers cleanup responsibility to the installer.
    func takeForInstallation() -> ModImportPreview? {
        relinquishPreview()
    }

    /// Removes temporary files without blocking the caller.
    func discardInBackground() {
        guard let preview = relinquishPreview() else {
            return
        }

        Task.detached(priority: .utility) {
            ModLibrary.discardImportPreview(preview)
        }
    }

    /// Removes temporary files and waits until cleanup has finished.
    func discard() async {
        guard let preview = relinquishPreview() else {
            return
        }

        await Task.detached(priority: .utility) {
            ModLibrary.discardImportPreview(preview)
        }.value
    }

    deinit {
        discardInBackground()
    }

    private func relinquishPreview() -> ModImportPreview? {
        ownedPreview.withLock { ownedPreview in
            defer {
                ownedPreview = nil
            }
            return ownedPreview
        }
    }
}
