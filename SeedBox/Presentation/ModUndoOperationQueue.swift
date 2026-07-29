import Foundation

/// Serializes file-backed Undo and Redo operations.
///
/// `UndoManager` is synchronous, while Seed Box mutations cross to an actor.
/// Chaining the operations preserves the order in which the user invoked Undo
/// and Redo. A queued inverse only runs when the preceding operation succeeded,
/// so a failed Undo cannot be followed by a state-changing Redo.
@MainActor
final class ModUndoOperationQueue {
    private struct Tail {
        var id: UUID
        var task: Task<Bool, Never>
    }

    private var tail: Tail?

    var isIdle: Bool {
        tail == nil
    }

    func enqueue(_ operation: @escaping @MainActor () async -> Bool) {
        let predecessor = tail?.task
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            let predecessorSucceeded = if let predecessor {
                await predecessor.value
            } else {
                true
            }
            let succeeded = predecessorSucceeded ? await operation() : false
            self?.finish(id: id)
            return succeeded
        }
        tail = Tail(id: id, task: task)
    }

    func waitUntilIdle() async {
        while let task = tail?.task {
            _ = await task.value
        }
    }

    private func finish(id: UUID) {
        guard tail?.id == id else {
            return
        }
        tail = nil
    }
}
