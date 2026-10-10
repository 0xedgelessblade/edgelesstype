import Foundation

public enum SentencePunctuation {
    private static let marks = Set("，。！？；：、,.!?;:")

    /// Accept only added sentence marks. Every original Character, including
    /// whitespace and punctuation, must remain in order and unchanged.
    public static func validated(_ candidate: String, preserving original: String) -> String? {
        guard SpeechContent.hasWords(original) else { return nil }
        let source = Array(original), output = Array(candidate)
        guard output.count <= source.count + max(8, source.count / 2) else { return nil }
        // Protect explicit code and technical tokens, including their end:
        // appending a dot to a URL or path can change what gets opened.
        let pattern = #"`[^`]*`|(?:https?://|www\.)[^\s，。！？；]+|[\w.+-]+@[\w.-]+|(?:~?/|\./)[^\s，。！？；]+"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let protected = regex.matches(in: original, range: NSRange(original.startIndex..., in: original)).map(\.range)
        var index = 0, utf16Offset = 0, added = 0
        var repaired = "", afterInsertedMark = false
        for char in output {
            // Models often replace a boundary space with a comma. Restore that
            // original space locally rather than accepting whitespace deletion.
            while afterInsertedMark, index < source.count,
                  source[index].isWhitespace, !source[index].isNewline, char != source[index] {
                repaired.append(source[index])
                utf16Offset += String(source[index]).utf16.count
                index += 1
            }
            if index < source.count, char == source[index] {
                utf16Offset += String(char).utf16.count
                index += 1
                repaired.append(char)
                afterInsertedMark = false
                continue
            }
            guard marks.contains(char), index > 0 else { return nil }
            if protected.contains(where: { utf16Offset > $0.location && utf16Offset <= NSMaxRange($0) }) { return nil }
            // An ASCII token may be a word, decimal, identifier or command.
            // Do not allow punctuation to split it, even if the model asks.
            func asciiToken(_ value: Character) -> Bool {
                value.unicodeScalars.allSatisfy { $0.isASCII && !CharacterSet.whitespacesAndNewlines.contains($0) }
            }
            if index < source.count, asciiToken(source[index-1]), asciiToken(source[index]) { return nil }
            added += 1
            guard added <= max(8, source.count / 2) else { return nil }
            repaired.append(char)
            afterInsertedMark = true
        }
        return index == source.count ? repaired : nil
    }
}
