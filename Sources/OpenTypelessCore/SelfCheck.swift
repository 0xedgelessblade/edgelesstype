import Foundation

public enum SelfCheck {
    public static func run() -> Int32 {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        expect(Hotkey.decide(session: .idle, tap: .fn) == .startDictation, "Fn 應該開始聽寫")
        expect(Hotkey.decide(session: .dictation, tap: .fn) == .stopDictation, "再按 Fn 應該結束聽寫")
        expect(Hotkey.decide(session: .idle, tap: .fnShift) == .startTranslation, "Fn+Shift 應該開始翻譯")
        expect(Hotkey.decide(session: .translation, tap: .fn) == .stopTranslation, "單按 Fn 應該結束翻譯")
        expect(Hotkey.decide(session: .translation, tap: .fnShift) == .ignore, "翻譯中再按 Fn+Shift 不該結束")
        expect(Hotkey.classify(FnGesture(duration: 2, shiftDuring: false)) == nil, "長按不該開始")
        expect(Hotkey.classify(FnGesture(duration: 0.2, shiftDuring: true)) == .fnShift, "短按 Fn+Shift 應該算翻譯")

        expect(Policy.plan(mode: .dictation, transcript: "今天很好。", polishEnabled: false) == .pasteRough("今天很好。"), "聽寫應該先貼粗稿")
        expect(Policy.plan(mode: .translation, transcript: "今天很好", polishEnabled: true) == .waitForEnglish(chinese: "今天很好"), "翻譯不該先貼中文")
        expect(ChatDraft.polish(text: "嗯").model == "grok-4.3", "潤飾模型不對")
        expect(ChatDraft.polish(text: "嗯").reasoningEffort == nil, "潤飾不該推理")
        expect(ChatDraft.translate(text: "嗯").model == "grok-4.7", "翻譯模型不對")
        expect(ChatDraft.translate(text: "嗯").reasoningEffort == "high", "翻譯應該用較慢的流暢設定")
        expect(ChatDraft.translate(text: "嗯").sendsAudio == false, "不該送錄音")
        expect(AudioInput.pick(from: "AVFoundation audio devices:\n[0] Steam Streaming Speakers\n[1] MacBook Air的麥克風\n", fallback: ":0") == ":1", "不該錄到喇叭")
        expect(Terms.prompt(terms: ["Hermes", "權限"]).contains("Hermes, 權限"), "常用詞沒交給辨識")
        expect(Terms.prompt(terms: ["Hermes"]).contains("。"), "提示要帶標點，辨識才會模仿")
        expect(!Terms.prompt(terms: ["Hermes"]).contains("請"), "提示不該是指令")
        expect(!Terms.prompt(terms: ["權限"]).contains("全選"), "不該把日常用詞寫成聽錯")

        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("open-typeless-selfcheck-\(UUID().uuidString)", isDirectory: true)
        let locations = SecretLocations(
            keyringDirectory: root.appendingPathComponent("keys", isDirectory: true),
            keyringFile: root.appendingPathComponent("keys/ring.json"),
            storeFile: root.appendingPathComponent("private/store.encrypted.json")
        )
        do {
            let store = SecretStore(locations: locations)
            let secret = Data("self-check-secret".utf8)
            try store.save(secret: secret)
            let read = try store.readSecret()
            expect(read == secret, "金鑰往返失敗")
            let synced = try String(contentsOf: locations.storeFile, encoding: .utf8)
            expect(!synced.contains("self-check-secret"), "同步檔出現明碼")
            let mode = try FileManager.default.attributesOfItem(atPath: locations.keyringFile.path)[.posixPermissions] as? Int
            expect(mode == 0o600, "金鑰表權限不是 600")
            let bad = SecretLocations(
                keyringDirectory: URL(fileURLWithPath: "/tmp/GoogleDrive/keys", isDirectory: true),
                keyringFile: URL(fileURLWithPath: "/tmp/GoogleDrive/keys/ring.json"),
                storeFile: locations.storeFile
            )
            do {
                try SecretStore(locations: bad).save(secret: secret)
                failures.append("不該把鑰匙寫進同步路徑")
            } catch SecretError.refusingSyncedFolder {
            } catch {
                failures.append("同步路徑的錯誤種類不對")
            }
        } catch {
            failures.append("金鑰自測沒有跑完")
        }
        try? FileManager.default.removeItem(at: root)

        if failures.isEmpty {
            FileHandle.standardOutput.write(Data("自測通過\n".utf8))
            return 0
        }
        let text = failures.joined(separator: "\n") + "\n"
        FileHandle.standardError.write(Data(text.utf8))
        return 1
    }
}
