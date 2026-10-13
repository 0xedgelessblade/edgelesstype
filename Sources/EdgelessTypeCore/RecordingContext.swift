import Foundation

/// Ephemeral, one-recording handoff. Closing it rejects late AX replies.
public final class RecordingContext: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var text: String?
    public init() {}
    public func supply(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        text = String(value.components(separatedBy: .controlCharacters).joined(separator: " ").prefix(160))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public func take() -> String? {
        lock.lock(); defer { lock.unlock() }
        closed = true
        let result = text; text = nil
        return result
    }
    public func discard() { _ = take() }
    public static func allowsField(role: String, subrole: String?, protected: Bool) -> Bool {
        guard !protected, subrole != "AXSecureTextField" else { return false }
        return role == "AXTextArea" || (["AXTextField", "AXComboBox"].contains(role) && subrole != nil)
    }
    public static func range(cursor: Int, count: Int) -> NSRange? {
        guard cursor >= 0, count > 0, cursor <= count else { return nil }
        let start = max(0, cursor - 120)
        return NSRange(location: start, length: min(count - start, 160))
    }
    public static func prompt(terms: String, context: String?) -> String {
        guard let context, !context.isEmpty else { return terms }
        return terms + "\n" + String(context.components(separatedBy: .controlCharacters).joined(separator: " ").prefix(160))
    }
}
