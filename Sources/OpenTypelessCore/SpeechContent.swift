import Foundation

public enum SpeechContent {
    /// A bare full stop, whitespace, or invisible formatting is not dictation.
    /// Keep numbers, code with letters, mixed languages, and actual emoji.
    public static func hasWords(_ text: String) -> Bool {
        let marker = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["[blank_audio]", "[silence]", "[no_speech]", "(silence)"].contains(marker) { return false }
        return text.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0.properties.isEmojiPresentation
        }
    }

    /// Only recognizes digital silence in the recorder's PCM16 WAV format.
    /// Unsupported/corrupt formats return nil, never a guessed silence result.
    public static func isDigitalSilence(_ data: Data) -> Bool? {
        let bytes = [UInt8](data)
        func name(_ at: Int, _ value: String) -> Bool { at+4 <= bytes.count && Array(bytes[at..<at+4]) == Array(value.utf8) }
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at+1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at+2) << 16 }
        guard bytes.count >= 12, name(0,"RIFF"), name(8,"WAVE") else { return nil }
        var offset = 12
        var pcm16 = false
        var samples: Range<Int>?
        while offset+8 <= bytes.count {
            let count = u32(offset+4), start = offset+8
            guard count <= bytes.count-start else { return nil }
            if name(offset,"fmt ") {
                guard count >= 16 else { return nil }
                pcm16 = u16(start) == 1 && u16(start+14) == 16 && u16(start+2) > 0
            }
            if name(offset,"data") { samples = start..<start+count }
            offset = start+count+(count & 1)
        }
        guard pcm16, let samples, samples.count.isMultiple(of: 2) else { return nil }
        for at in stride(from: samples.lowerBound, to: samples.upperBound, by: 2) {
            let value = Int(Int16(bitPattern: UInt16(u16(at))))
            if abs(value) > 1 { return false }
        }
        return true
    }
}
