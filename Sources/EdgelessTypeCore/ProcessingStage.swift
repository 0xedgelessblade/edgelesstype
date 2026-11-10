import Foundation

public enum ProcessingStage: String, CaseIterable {
    case uploading, recognizing, correcting, translating
    public var title: String {
        switch self {
        case .uploading: return "傳送音訊中"
        case .recognizing: return "語音辨識中"
        case .correcting: return "文字校正中"
        case .translating: return "翻譯中"
        }
    }
}

public enum ProcessingPlan {
    public static func separateCorrection(mode: Session, enabled: Bool) -> Bool {
        enabled && mode == .dictation
    }
    public static func shouldOfferRoughPaste(stage: ProcessingStage, elapsed: TimeInterval) -> Bool {
        (stage == .correcting || stage == .translating) && elapsed >= 3
    }
    /// A slow cloud recognition can be abandoned for local Whisper on the same recording.
    public static func shouldOfferLocalRecognition(stage: ProcessingStage, elapsed: TimeInterval) -> Bool {
        (stage == .uploading || stage == .recognizing) && elapsed >= 2
    }
}

/// What happens to a recording, in one line. Every settings window shows this same text, so they cannot disagree.
public enum PipelineSummary {
    public static func dictation(backend: TranscriptionBackend, cloud: CloudPreferences, correctionEnabled: Bool) -> String {
        if backend.mergesCorrection {
            return "辨識＋校正：\(backend.statusTitle)" + (backend.cloudModel.map { "（\($0)）" } ?? "")
        }
        let correction = correctionEnabled ? "\(cloud.provider.title) \(cloud.correctionModel(for: cloud.provider))" : "關閉"
        return "辨識：\(backend.statusTitle)　→　校正：\(correction)"
    }
    public static func translation(cloud: CloudPreferences) -> String {
        "中翻英：\(cloud.provider.title) \(cloud.provider.model(for: .translation))"
    }
}
