import AppKit

/// A short-lived, memory-only backup. Restore only after destination readback
/// confirms insertion, and only while our published clipboard is still current.
final class ClipboardLease {
    private let board: NSPasteboard
    private var backup: [[NSPasteboard.PasteboardType: Data]]?
    private(set) var publishedCount: Int?
    init(board: NSPasteboard = .general) { self.board = board }

    func publish(_ text: String) -> Bool {
        discard()
        backup = snapshot()
        board.clearContents()
        guard board.setString(text, forType: .string) else { discard(); return false }
        publishedCount = board.changeCount
        return true
    }

    @discardableResult func finish(confirmed: Bool) -> Bool {
        guard confirmed, let backup, let publishedCount else { return false }
        // Prepare independent eager items before checking ownership, so reading
        // old data never delays the final change-count check.
        let items = backup.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        guard board.changeCount == publishedCount else { discard(); return false }
        let ourText = board.string(forType: .string)
        board.clearContents()
        let emptyCount = board.changeCount
        let restored = items.isEmpty || board.writeObjects(items)
        // A failed write must not leave an empty clipboard. Do not replace a
        // newer clipboard item even on this uncommon error path.
        if !restored, board.changeCount == emptyCount, let ourText {
            _ = board.setString(ourText, forType: .string)
        }
        discard()
        return restored
    }

    func discard() { backup = nil; publishedCount = nil }

    private func snapshot() -> [[NSPasteboard.PasteboardType: Data]]? {
        let version = board.changeCount
        var result: [[NSPasteboard.PasteboardType: Data]] = []
        var remaining = 64 * 1024 * 1024
        for item in board.pasteboardItems ?? [] {
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type), data.count <= remaining else { return nil }
                remaining -= data.count
                values[type] = data
            }
            result.append(values)
        }
        return board.changeCount == version ? result : nil
    }
}
