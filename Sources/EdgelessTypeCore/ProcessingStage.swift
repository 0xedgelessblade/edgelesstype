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
}
