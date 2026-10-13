import Foundation
import EdgelessTypeCore

enum ContextCorrectionService {
    static func correct(_ text: String, settings: VocabularySettings, config: AppConfig, cancellation: ProcessingCancellation? = nil) throws -> String {
        try cancellation?.check()
        let entries = ContextCorrection.candidates(in: text, settings: settings)
        guard settings.contextCorrectionEnabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        let provider = try CloudAccess.preferences.load().provider
        return try ContextCorrection.correctFullText(text) { chunk in
            try cancellation?.check()
            let body = try ContextCorrection.draft(text: chunk, entries: entries,
                model: provider.model(for: .correction), timeout: provider.correctionTimeoutSeconds)
            return try CloudAccess.complete(body, purpose: .correction, cancellation: cancellation)
        }
    }

    static func probe(onlyProtest: Bool = false, onlyPunctuation: Bool = false) -> Int32 {
        do {
            let config = try AppPaths.loadConfig()
            let saved = try AppPaths.vocabularyStore.load(fallbackTerms: config.terms)
            // Exercise the same simple word-only input a user can add in UI.
            let settings = VocabularySettings(contextCorrectionEnabled: saved.contextCorrectionEnabled,
                entries: saved.entries.map { VocabularyEntry(word: $0.word) })
            guard settings.contextCorrectionEnabled else { print("contextCorrectionEnabled=false"); return 2 }
            let allCases = [
                ("家人抬官抗議。", "家人抬棺抗議。"),
                ("台官抗議", "抬棺抗議"),
                ("台灣官員抗議不公平待遇。", "台灣官員抗議不公平待遇。"),
                ("人定聖天。", "人定勝天。"),
                ("現在一愁莫展。", "現在一籌莫展。"),
                ("他是古代的聖人。", "他是古代的聖人。"),
                ("Please check 麥克風全線，then restart the app。", "Please check 麥克風權限，then restart the app。"),
                ("API returns a JSON object，這段 English 保留。", "API returns a JSON object，這段 English 保留。"),
                ("請打開麥克風的全線。", "請打開麥克風的權限。"),
                ("這條捷運今天全線通車。", "這條捷運今天全線通車。"),
                ("請全選這段文字，再檢查應用程式的全線。", "請全選這段文字，再檢查應用程式的權限。"),
                ("文字提示框貼完之後沒有自己推出。", "文字提示框貼完之後沒有自己退出。"),
                ("公司今天推出新產品。", "公司今天推出新產品。"),
                ("先把推車推出門外。", "先把推車推出門外。"),
                ("打開麥克風全線，再查捷運全線通車。", "打開麥克風權限，再查捷運全線通車。"),
                ("請在設定中允許錄音全線。", "請在設定中允許錄音權限。"),
                ("按取消後，這個程式就會推出。", "按取消後，這個程式就會退出。"),
                ("這間公司準備推出新工具。", "這間公司準備推出新工具。"),
                ("全線", "全線"),
                ("推出", "推出"),
                ("把這句貼到荷米史的對話框。", "把這句貼到Hermes的對話框。")
            ]
            let punctuationCases = [
                ("今天先整理專案文件明天再測試語音輸入最後把結果記錄下來", "今天先整理專案文件明天再測試語音輸入最後把結果記錄下來"),
                ("這個 App 可以正常使用，接著 check the settings。", "這個 App 可以正常使用，接著 check the settings。"),
                ("我先打開設定然後重新啟動程式你可以幫我看看嗎", "我先打開設定然後重新啟動程式你可以幫我看看嗎"),
                ("請幫我 check the settings 然後 restart the app 好嗎", "請幫我 check the settings 然後 restart the app 好嗎"),
                ("請打開麥克風全線然後 check the settings 可以嗎", "請打開麥克風權限然後 check the settings 可以嗎")
            ]
            let cases = onlyPunctuation ? punctuationCases : (onlyProtest ? allCases.filter { $0.0.contains("抗議") } : allCases)
            var failures = 0
            for (input, expected) in cases {
                let start = Date()
                do {
                    let draft = try ContextCorrection.draft(text: input, entries: settings.entries,
                        model: try CloudAccess.preferences.load().provider.model(for: .correction))
                    let response = try CloudAccess.complete(draft, purpose: .correction)
                    if onlyPunctuation { print("fixed-punctuation-response: \(response)") }
                    let actual = try ContextCorrection.acceptFullText(response)
                    let preserved = SentencePunctuation.validated(actual, preserving: expected) != nil
                    // Short mixed-language requests need a sentence ending,
                    // not one arbitrary comma placement. Long Chinese clauses
                    // also exercise internal sentence boundaries.
                    let needsComma = onlyPunctuation && !input.contains(" ")
                    let passed = preserved && (!needsComma || actual.contains("，")) &&
                        (!onlyPunctuation || actual.hasSuffix(input.hasSuffix("嗎") ? "？" : "。"))
                    if !passed { failures += 1; print("fixed-failed-response: \(response)") }
                    print("\(passed ? "PASS" : "FAIL") \(String(format: "%.2f", Date().timeIntervalSince(start)))s | \(input) -> \(actual)")
                } catch {
                    failures += 1
                    print("FAIL service-error:\((error as? CloudError)?.rawValue ?? "unknown") | \(input)")
                }
            }
            print("context-correction: \(cases.count - failures)/\(cases.count)")
            return failures == 0 ? 0 : 1
        } catch { print("correction-probe setup failed"); return 2 }
    }
}
