import Foundation

public enum OutputConversionError: LocalizedError {
    case unavailable
    public var errorDescription: String? { "繁體中文轉換失敗，本次沒有輸出文字。請重新嘗試。" }
}

public enum OutputPolicy {
    /// All Chinese result text crosses this local gate, including fallback,
    /// model output and translation leftovers. Never return the source on error.
    public static func traditional(_ text: String) throws -> String {
        guard let result = text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) else {
            throw OutputConversionError.unavailable
        }
        return result
    }

    public static func correctionWarning(outcome: String) -> String? {
        if outcome.hasPrefix("rejected:"), let reason = CorrectionRejection(rawValue: String(outcome.dropFirst("rejected:".count))) {
            return reason.explanation + "\n已保留繁體文字，標點可能不完整。"
        }
        switch outcome {
        case "corrected", "unchanged", "not_requested": return nil
        case "quota":
            return "服務端額度不足或請求過於頻繁。\n請檢查服務商帳戶或稍後再試。"
        case "rejected":
            return "校正回覆未通過內容檢查。\n已保留繁體文字，標點可能不完整。"
        default:
            let reason = CloudError(rawValue: outcome)?.errorDescription ?? "校正請求失敗，請稍後再試。"
            return reason + "\n已保留繁體文字，標點可能不完整。"
        }
    }
}
