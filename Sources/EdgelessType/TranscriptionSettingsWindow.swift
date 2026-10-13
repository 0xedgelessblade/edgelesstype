import AppKit
import EdgelessTypeCore

final class TranscriptionSettingsWindow: NSWindowController {
    var onSave: ((TranscriptionPreferences) throws -> Void)?
    var onOpenAIKey: (() -> Void)?
    private let store: TranscriptionPreferencesStore
    private let backend = NSPopUpButton(frame: .zero, pullsDown: false)
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let consent = NSButton(checkboxWithTitle: "我同意將之後的錄音傳送至 OpenAI 進行轉寫。", target: nil, action: nil)
    private let saveButton = NSButton(title: "儲存選擇", target: nil, action: nil)
    private let keyButton = NSButton(title: "OpenAI 金鑰設定…", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")

    init(store: TranscriptionPreferencesStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 410), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "edgelesstype — 語音辨識"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build(); refresh(); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var selected: TranscriptionBackend { backend.indexOfSelectedItem == 1 ? .openAI : .localWhisper }
    private func build() {
        guard let view = window?.contentView else { return }
        let title = NSTextField(labelWithString: "語音辨識方式")
        title.font = .systemFont(ofSize: 24, weight: .semibold); title.frame = NSRect(x: 26, y: 344, width: 560, height: 36)
        let subtitle = NSTextField(wrappingLabelWithString: "第一步：把錄音轉成文字。這與後面的文字校正／翻譯服務分開設定。")
        subtitle.textColor = .secondaryLabelColor; subtitle.frame = NSRect(x: 26, y: 292, width: 565, height: 42)
        backend.addItems(withTitles: TranscriptionBackend.allCases.map(\.title))
        backend.frame = NSRect(x: 26, y: 245, width: 566, height: 34)
        backend.target = self; backend.action = #selector(changed)
        backend.setAccessibilityLabel("語音辨識方式")
        detail.font = .systemFont(ofSize: 13); detail.frame = NSRect(x: 28, y: 155, width: 562, height: 80)
        consent.frame = NSRect(x: 26, y: 119, width: 566, height: 28)
        keyButton.frame = NSRect(x: 26, y: 65, width: 218, height: 34)
        keyButton.bezelStyle = .rounded; keyButton.target = self; keyButton.action = #selector(openKey)
        saveButton.frame = NSRect(x: 386, y: 65, width: 204, height: 34)
        saveButton.bezelStyle = .rounded; saveButton.target = self; saveButton.action = #selector(save)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 26, y: 12, width: 566, height: 43)
        for control in [title, subtitle, backend, detail, consent, keyButton, saveButton, status] { view.addSubview(control) }
    }
    func refresh() {
        do {
            let preferences = try store.load()
            backend.selectItem(at: preferences.backend == .openAI ? 1 : 0)
            consent.state = preferences.cloudAudioConsent ? .on : .off
            status.stringValue = "目前使用：" + preferences.backend.title
        } catch {
            backend.selectItem(at: 0); consent.state = .off
            status.stringValue = "設定無法讀取；尚未變更原有設定。請重新選擇並儲存。"
        }
        updateDetails()
    }
    @objc private func changed() {
        if selected == .localWhisper { consent.state = .off }
        status.stringValue = "尚未儲存。"; updateDetails()
    }
    private func updateDetails() {
        let cloud = selected == .openAI
        consent.isHidden = !cloud; keyButton.isEnabled = cloud
        detail.stringValue = cloud
            ? "使用 OpenAI gpt-transcribe，需要網路與 API 額度。\n每次結束錄音後，音訊將傳送至 OpenAI；單次錄音上限 25 MB。\n沿用 OpenAI 金鑰，不改變文字校正服務商。輸出仍轉為繁體中文。"
            : "使用本機 Whisper Small／Large-v3 Turbo，錄音不會送到雲端。\n可從選單選擇本機模型。後續文字校正與翻譯仍依原有設定處理。"
        saveButton.title = cloud ? "儲存雲端選擇" : "使用本機 Whisper"
    }
    @objc private func openKey() { onOpenAIKey?() }
    @objc private func save() {
        do {
            let preferences = try TranscriptionPreferences(backend: selected, cloudAudioConsent: selected == .openAI && consent.state == .on).validated()
            if let onSave { try onSave(preferences) } else { try store.save(preferences) }
            status.stringValue = "已儲存；下一次錄音使用：" + preferences.backend.title
        } catch { status.stringValue = (error as? TranscriptionError)?.errorDescription ?? "儲存失敗，原有選擇未變更。" }
    }
}
