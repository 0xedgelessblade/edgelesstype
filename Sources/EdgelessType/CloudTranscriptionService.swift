import Foundation
import EdgelessTypeCore

/// Explicit opt-in cloud recognition. Exactly one backend runs; nothing falls back to another provider.
enum CloudTranscriptionService {
    static func transcribe(url: URL, preferences: TranscriptionPreferences, terms: [String] = [], onProgress: ((Double) -> Void)? = nil,
                           onTimings: ((TranscriptionTransferTimings) -> Void)? = nil, onFailureEvidence: (([String: String]) -> Void)? = nil,
                           context: String? = nil, cancellation: ProcessingCancellation? = nil) throws -> String {
        try cancellation?.check()
        let backend = try preferences.validated().backend
        guard backend.isCloud, !CloudAccess.offlineProbe, let provider = backend.cloudProvider else { throw TranscriptionError.cloudNotEnabled }
        let limit = backend == .openAI ? OpenAITranscriptionWire.maximumAudioBytes : GeminiAudioWire.maximumAudioBytes
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw TranscriptionError.audioUnavailable }
        guard size <= limit else { throw TranscriptionError.audioTooLarge }
        guard let audio = try? Data(contentsOf: url) else { throw TranscriptionError.audioUnavailable }
        let key: String
        do { key = String(decoding: try CloudAccess.store(provider).readSecret(), as: UTF8.self) }
        catch { throw provider == .google ? TranscriptionError.missingGoogleKey : TranscriptionError.missingOpenAIKey }
        switch backend {
        case .openAI:
            return try CloudAudioClient.shared.transcribe(audio: audio, preferences: preferences, key: key, onProgress: onProgress, onTimings: onTimings, context: context, cancellation: cancellation)
        case .geminiTranscribe, .geminiDirect:
            return try CloudAudioClient.shared.transcribeGemini(audio: audio, backend: backend, preferences: preferences, key: key, terms: terms,
                onProgress: onProgress, onTimings: onTimings, onFailureEvidence: onFailureEvidence, context: context, cancellation: cancellation)
        case .localWhisper:
            throw TranscriptionError.cloudNotEnabled
        }
    }
}
