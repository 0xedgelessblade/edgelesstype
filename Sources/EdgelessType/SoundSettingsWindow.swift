import AppKit
import EdgelessTypeCore

final class SoundSettingsWindow: NSWindowController, NSWindowDelegate {
    private let player: SoundPlayer
    private let chooser = NSPopUpButton()
    private let message = NSTextField(wrappingLabelWithString: "")
    var onClose: (() -> Void)?

    init(player: SoundPlayer) {
        self.player = player
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 225),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "edgelesstype — 提示音"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        guard let view = window.contentView else { return }
        let title = NSTextField(labelWithString: "提示音")
        title.font = .boldSystemFont(ofSize: 24); title.frame = NSRect(x: 25, y: 166, width: 400, height: 36)
        view.addSubview(title)
        chooser.frame = NSRect(x: 25, y: 116, width: 310, height: 32)
        chooser.addItems(withTitles: SoundPreset.allCases.map(\.title))
        chooser.setAccessibilityLabel("提示音組合")
        chooser.target = self; chooser.action = #selector(selectPreset)
        view.addSubview(chooser)
        let preview = NSButton(title: "試聽", target: self, action: #selector(preview))
        preview.bezelStyle = .rounded; preview.frame = NSRect(x: 350, y: 115, width: 105, height: 34)
        view.addSubview(preview)
        let hint = NSTextField(wrappingLabelWithString: "試聽依序播放「開始音 → 結束音」。\n選擇會自動儲存，下次錄音生效。")
        hint.frame = NSRect(x: 25, y: 54, width: 430, height: 46)
        hint.textColor = .secondaryLabelColor; view.addSubview(hint)
        message.frame = NSRect(x: 25, y: 16, width: 430, height: 30)
        message.textColor = .secondaryLabelColor; view.addSubview(message)
        refresh(); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh() { chooser.selectItem(at: SoundPreset.allCases.firstIndex(of: player.preset) ?? 0) }
    @objc private func selectPreset() {
        let selected = SoundPreset.allCases[chooser.indexOfSelectedItem]
        do { try player.select(selected); message.stringValue = "已儲存：\(selected.title)" }
        catch { refresh(); message.stringValue = "沒有儲存成功，仍沿用原本選擇。" }
    }
    @objc private func preview() {
        message.stringValue = player.preview() ? "正在試聽：\(player.preset.title)" : "找不到提示音檔案。"
    }
    func windowWillClose(_ notification: Notification) { player.cancelPreview(); onClose?() }
}
