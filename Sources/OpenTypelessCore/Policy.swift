import Foundation

public enum InsertPlan: Equatable {
    case pasteRough(String)
    case waitForEnglish(chinese: String)
    case drop(String)
}

public enum Policy {
    public static let fillers = ["呃", "嗯", "那個", "就是", "然後", "啊", "喔"]

    public static func needsPolish(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if fillers.contains(where: { trimmed.contains($0) }) {
            return true
        }
        if hasImmediateRepeat(trimmed) {
            return true
        }
        guard let end = trimmed.last else { return false }
        let punct: Set<Character> = ["。", "！", "？", ".", "!", "?", "…", "」", "）", ")"]
        return !punct.contains(end)
    }

    public static func plan(mode: Session, transcript: String, polishEnabled: Bool) -> InsertPlan {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpeechContent.hasWords(trimmed) else {
            return .drop("沒有聽到字")
        }
        switch mode {
        case .dictation:
            return .pasteRough(trimmed)
        case .translation:
            return .waitForEnglish(chinese: trimmed)
        case .idle:
            return .drop("沒有在錄音")
        }
    }

    public static func shouldCallPolish(transcript: String, polishEnabled: Bool) -> Bool {
        polishEnabled && needsPolish(transcript)
    }

    static func hasImmediateRepeat(_ text: String) -> Bool {
        let chars = Array(text)
        guard chars.count >= 2 else { return false }
        for index in 1..<chars.count where chars[index] == chars[index - 1] && !chars[index].isWhitespace && !chars[index].isPunctuation {
            if chars[index].isLetter || isCJK(chars[index]) {
                return true
            }
        }
        return false
    }

    static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value)
    }
}

public struct ChatBody: Equatable {
    public var model: String
    public var timeoutSeconds: TimeInterval
    public var reasoningEffort: String?
    public var system: String
    public var user: String
    public var temperature: Double = 0.3
    public var jsonOutput = false

    public init(model: String, timeoutSeconds: TimeInterval, reasoningEffort: String?, system: String, user: String) {
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.reasoningEffort = reasoningEffort
        self.system = system
        self.user = user
    }

    public var json: [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        if let reasoningEffort {
            payload["reasoning_effort"] = reasoningEffort
        }
        if jsonOutput { payload["response_format"] = ["type": "json_object"] }
        return payload
    }

    public var sendsAudio: Bool {
        false
    }
}

public enum ChatDraft {
    public static let polishModel = CloudProvider.xai.model(for: .correction)
    public static let translateModel = CloudProvider.xai.model(for: .translation)

    public static func polish(text: String, timeout: TimeInterval = 1.2) -> ChatBody {
        ChatBody(
            model: polishModel,
            timeoutSeconds: timeout,
            reasoningEffort: nil,
            system: "你只做三件事：去掉贅字和重複、補上標點、維持原意。不要摘要，不要加例子，中英夾雜要原樣保留英文單字、詞組、句子、大小寫、程式碼與網址，不要翻譯成中文。中文維持繁體，只輸出整理後的原文，不要解釋。",
            user: text
        )
    }

    public static func translate(text: String, timeout: TimeInterval = 25, reasoningEffort: String = "high") -> ChatBody {
        ChatBody(
            model: translateModel,
            timeoutSeconds: timeout,
            reasoningEffort: reasoningEffort,
            system: "You translate spoken Chinese into fluent, natural English. The input is a speech-to-text draft. It may be Traditional or Simplified, and it may contain filler words. Keep the speaker's meaning. Prefer natural English over word-for-word translation. Do not summarize, do not add examples, and do not explain. Keep names and product names that are already in English. Output only the English text.",
            user: text
        )
    }
}

public enum AudioInput {
    public static func pick(from listing: String, fallback: String) -> String {
        var inAudio = false
        var bestScore = 0
        var best = ""
        for raw in listing.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.contains("audio devices") {
                inAudio = true
                continue
            }
            if line.contains("video devices") {
                inAudio = false
            }
            guard inAudio, let open = line.lastIndex(of: "["), let close = line.lastIndex(of: "]"), open < close else {
                continue
            }
            let index = line[line.index(after: open)..<close]
            guard index.allSatisfy(\.isNumber) else { continue }
            let name = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            let score = score(name)
            if score > bestScore {
                bestScore = score
                best = ":\(index)"
            }
        }
        return best.isEmpty ? fallback : best
    }

    private static func score(_ name: String) -> Int {
        let lower = name.lowercased()
        var value = 0
        if name.contains("麥克風") || lower.contains("microphone") { value += 10 }
        if name.contains("MacBook") || lower.contains("built-in") || name.contains("內建") { value += 5 }
        if lower.contains("steam") || lower.contains("speaker") || name.contains("喇叭")
            || lower.contains("blackhole") || lower.contains("loopback") {
            value -= 20
        }
        return value
    }
}

public enum PermissionPane {
    public static let inputMonitoring = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
}

public enum Terms {
    public static func prompt(terms: [String]) -> String {
        let sample = "這個 App 現在可以正常使用，接著 check the settings。"
        let kept = terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !kept.isEmpty else { return sample }
        return sample + " " + kept.joined(separator: ", ")
    }
}

public enum Promise {
    public static let beforePermission = """
    這支程式要三個權限，現在還沒有向系統開口。

    麥克風：只有你短按 Fn 之後才錄音。聲音留在這台電腦，轉成文字就刪，不會把錄音傳出去。
    輔助使用：把文字貼進你正在用的程式。風險是它能模擬貼上。會短暫讀取目標輸入框確認貼入，不上傳框內原有文字。
    輸入監控：才能收到 Fn。它只拿走 Fn，其他鍵照常給系統。

    程式開著時，Fn 不會再開出表情符號。關掉就恢復。
    金鑰若有保存，只以密文放在這個資料夾，解開用的鑰匙在這台電腦自己的設定目錄，不進同步碟，也不進鑰匙圈。
    """
}
