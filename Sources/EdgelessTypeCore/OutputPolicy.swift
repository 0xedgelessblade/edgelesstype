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

    /// Apply the user's final-output style locally, after correction/translation.
    /// Leave punctuation inside the text, numbers, questions and exclamations intact.
    public static func forDelivery(_ text: String) throws -> String {
        var result = try traditional(text).trimmingCharacters(in: .whitespacesAndNewlines)
        while result.last == "." || result.last == "。" {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    public static func correctionWarning(outcome: String) -> String? {
        if outcome.hasPrefix("rejected:"), let reason = CorrectionRejection(rawValue: String(outcome.dropFirst("rejected:".count))) {
            return reason.explanation + "\n已保留繁體文字，標點可能不完整。"
        }
        switch outcome {
        case "corrected", "unchanged", "not_requested", "skipped": return nil
        case "quota":
            return "服務端額度不足或請求過於頻繁。\n請檢查服務商帳戶或稍後再試。"
        case "rejected":
            return "校正回覆未通過內容檢查。\n已保留繁體文字，標點可能不完整。"
        default:
            let reason = CloudError(rawValue: outcome)?.errorDescription ?? "校正請求失敗，請稍後再試。"
            return reason + "\n已保留繁體文字，標點可能不完整。"
        }
    }

    public static func correctionNotice(outcome: String) -> CorrectionNotice? {
        if outcome.hasPrefix("rejected:"), let reason = CorrectionRejection(rawValue: String(outcome.dropFirst("rejected:".count))) {
            return CorrectionNotice(label: "校正失敗", detail: reason.explanation)
        }
        switch outcome {
        case "corrected", "unchanged", "not_requested", "skipped":
            return nil
        case "offline":
            return CorrectionNotice(label: "離線", detail: CloudError.offline.errorDescription ?? "目前離線，未送出校正。")
        case "network":
            return CorrectionNotice(label: "無法連線", detail: CloudError.network.errorDescription ?? "無法連線，請檢查網路。")
        case "timeout":
            return CorrectionNotice(label: "逾時", detail: CloudError.timeout.errorDescription ?? "連線逾時，請稍後再試。")
        case "quota":
            return CorrectionNotice(label: "額度不足", detail: CloudError.quota.errorDescription ?? "API 額度不足或請求過於頻繁。")
        case "authentication", "invalidKey", "missingKey":
            let detail = CloudError(rawValue: outcome)?.errorDescription ?? "金鑰無效或沒有模型權限，請檢查服務商帳戶。"
            return CorrectionNotice(label: "金鑰問題", detail: detail, opensSettings: true)
        default:
            let detail = CloudError(rawValue: outcome)?.errorDescription ?? "校正請求失敗，請稍後再試。"
            return CorrectionNotice(label: "校正失敗", detail: detail)
        }
    }
}

public struct CorrectionNotice: Equatable {
    public var label: String
    public var detail: String
    public var opensSettings: Bool
    public init(label: String, detail: String, opensSettings: Bool = false) {
        self.label = label
        self.detail = detail
        self.opensSettings = opensSettings
    }
}
