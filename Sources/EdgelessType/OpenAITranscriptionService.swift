import Foundation
import EdgelessTypeCore

enum OpenAITranscriptionService {
    static func transcribe(url: URL, preferences: TranscriptionPreferences, onProgress: ((Double) -> Void)? = nil,
                           onTimings: ((TranscriptionTransferTimings) -> Void)? = nil, context: String? = nil, cancellation: ProcessingCancellation? = nil) throws -> String {
        try cancellation?.check()
        guard try preferences.validated().backend == .openAI, !CloudAccess.offlineProbe else { throw TranscriptionError.cloudNotEnabled }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw TranscriptionError.audioUnavailable }
        guard size <= OpenAITranscriptionWire.maximumAudioBytes else { throw TranscriptionError.audioTooLarge }
        guard let audio = try? Data(contentsOf: url) else { throw TranscriptionError.audioUnavailable }
        let key: String
        do { key = String(decoding: try CloudAccess.store(.openai).readSecret(), as: UTF8.self) }
        catch { throw TranscriptionError.missingOpenAIKey }
        return try OpenAITranscriptionClient.shared.transcribe(audio: audio, preferences: preferences, key: key, onProgress: onProgress, onTimings: onTimings, context: context, cancellation: cancellation)
    }
}
