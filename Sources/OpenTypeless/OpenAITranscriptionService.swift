import Foundation
import OpenTypelessCore

enum OpenAITranscriptionService {
    static func transcribe(url: URL, preferences: TranscriptionPreferences) throws -> String {
        guard try preferences.validated().backend == .openAI, !CloudAccess.offlineProbe else { throw TranscriptionError.cloudNotEnabled }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw TranscriptionError.audioUnavailable }
        guard size <= OpenAITranscriptionWire.maximumAudioBytes else { throw TranscriptionError.audioTooLarge }
        guard let audio = try? Data(contentsOf: url) else { throw TranscriptionError.audioUnavailable }
        let key: String
        do { key = String(decoding: try CloudAccess.store(.openai).readSecret(), as: UTF8.self) }
        catch { throw TranscriptionError.missingOpenAIKey }
        return try OpenAITranscriptionClient().transcribe(audio: audio, preferences: preferences, key: key)
    }
}
