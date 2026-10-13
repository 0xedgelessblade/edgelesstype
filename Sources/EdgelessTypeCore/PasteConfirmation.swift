import Foundation

/// Evidence comes from the destination field, never from clipboard reads or
/// the return value of an accessibility setter. AX ranges use UTF-16 offsets.
public struct PasteSnapshot {
    public var value: String?
    public var selection: NSRange?

    public init(value: String?, selection: NSRange?) {
        self.value = value
        self.selection = selection
    }
}

public enum PasteConfirmation {
    public static func confirms(_ text: String, before: PasteSnapshot, after: PasteSnapshot) -> Bool {
        guard !text.isEmpty, let old = before.value, let new = after.value else { return false }
        if let range = before.selection,
           range.location != NSNotFound, range.location >= 0, range.length >= 0,
           range.location <= (old as NSString).length,
           range.length <= (old as NSString).length - range.location {
            let expected = (old as NSString).replacingCharacters(in: range, with: text)
            if new == expected {
                // Replacing a selection with identical text still succeeds,
                // but merely seeing old matching text must not count.
                return new != old || (range.length > 0 && after.selection == NSRange(
                    location: range.location + (text as NSString).length, length: 0))
            }
        }
        // Web editors may omit selection offsets or expose placeholder text.
        // Require newly appearing text, not a pre-existing matching sentence.
        return new != old && occurrences(text, in: new) > occurrences(text, in: old)
    }

    private static func occurrences(_ text: String, in value: String) -> Int {
        value.components(separatedBy: text).count - 1
    }
}
