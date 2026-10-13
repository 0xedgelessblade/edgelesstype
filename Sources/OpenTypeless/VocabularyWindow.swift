import AppKit
import OpenTypelessCore

final class VocabularyWindow: NSWindowController, NSSearchFieldDelegate, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onSoundSettings: (() -> Void)?
    var onAPISettings: (() -> Void)?
    var onTranscriptionSettings: (() -> Void)?
    var onQuit: (() -> Void)?
    var onSave: ((VocabularySettings) throws -> Void)?
    private var settings: VocabularySettings
    private let search = NSSearchField()
    private let grid = DictionaryGridView()
    private let scroll = NSScrollView()
    private let countLabel = NSTextField(labelWithString: "")
    private let modelStatus = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let enabled = NSButton(checkboxWithTitle: "根據整句上下文校正", target: nil, action: nil)
    private var displayedIDs: [UUID] = []

    init(settings: VocabularySettings) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:780,height:612),
            styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "\(AppIdentity.displayName) — 字典"
        window.isReleasedWhenClosed = false
        super.init(window:window)
        window.minSize = NSSize(width:720,height:572)
        window.delegate = self
        build(); refresh(); window.center()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        guard let view = window?.contentView else { return }
        let title = NSTextField(labelWithString: "字典")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        let hint = NSTextField(labelWithString: "加入正確寫法，讓 edgelesstype 更認得你的常用詞。")
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabelColor
        let add = NSButton(title: "新增單字", target: self, action: #selector(addWord))
        add.bezelStyle = .rounded
        add.bezelColor = .controlAccentColor
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        add.imagePosition = .imageLeft
        let shortcuts = NSTextField(labelWithString: "Fn  開始／結束錄音    ·    Shift + Fn  中翻英")
        shortcuts.font = .systemFont(ofSize: 12, weight: .medium)
        shortcuts.textColor = .secondaryLabelColor
        let help = NSButton(title: "操作指南", target: self, action: #selector(showUsageGuide))
        help.bezelStyle = .inline
        help.font = .systemFont(ofSize: 12)
        help.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        help.imagePosition = .imageLeft
        let divider = NSBox()
        divider.boxType = .separator

        search.placeholderString = "搜尋字典"
        search.setAccessibilityLabel("搜尋字典")
        search.delegate = self
        search.controlSize = .large
        let sounds = NSButton(title: "提示音…", target: self, action: #selector(openSoundSettings))
        sounds.bezelStyle = .rounded
        sounds.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
        sounds.imagePosition = .imageLeft
        let speech = NSButton(title: "語音辨識…", target: self, action: #selector(openTranscriptionSettings))
        speech.bezelStyle = .rounded
        speech.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        speech.imagePosition = .imageLeft
        let api = NSButton(title: "API 設定…", target: self, action: #selector(openAPISettings))
        api.bezelStyle = .rounded
        api.image = NSImage(systemSymbolName: "key.horizontal", accessibilityDescription: nil)
        api.imagePosition = .imageLeft
        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        modelStatus.font = .systemFont(ofSize: 11)
        modelStatus.textColor = .tertiaryLabelColor
        modelStatus.alignment = .right
        modelStatus.lineBreakMode = .byTruncatingTail
        modelStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = grid
        let preferences = DictionaryCardView()
        enabled.state = settings.contextCorrectionEnabled ? .on : .off
        enabled.target = self
        enabled.action = #selector(toggleContext)
        enabled.font = .systemFont(ofSize: 13, weight: .medium)
        let privacy = NSTextField(wrappingLabelWithString: "開啟後，文字與字典送至校正服務。錄音是否上傳由「語音辨識」設定決定。")
        privacy.font = .systemFont(ofSize: 12)
        privacy.textColor = .secondaryLabelColor
        for child in [enabled, privacy] {
            child.translatesAutoresizingMaskIntoConstraints = false
            preferences.addSubview(child)
        }
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let quit = NSButton(title: "退出 App", target: self, action: #selector(quitApplication))
        quit.bezelStyle = .inline
        quit.font = .systemFont(ofSize: 12)
        quit.contentTintColor = .secondaryLabelColor

        for child in [title, hint, shortcuts, help, add, divider, search, sounds, speech, api, countLabel, modelStatus, scroll, preferences, status, quit] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        let searchWidth = search.widthAnchor.constraint(equalToConstant: 260)
        searchWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 26),
            title.heightAnchor.constraint(equalToConstant: 36),
            title.trailingAnchor.constraint(lessThanOrEqualTo: add.leadingAnchor, constant: -24),
            add.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            add.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            add.widthAnchor.constraint(equalToConstant: 122),
            add.heightAnchor.constraint(equalToConstant: 34),
            hint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            hint.heightAnchor.constraint(equalToConstant: 20),
            shortcuts.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            shortcuts.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            shortcuts.heightAnchor.constraint(equalToConstant: 20),
            shortcuts.trailingAnchor.constraint(lessThanOrEqualTo: help.leadingAnchor, constant: -20),
            help.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            help.centerYAnchor.constraint(equalTo: shortcuts.centerYAnchor),
            help.widthAnchor.constraint(equalToConstant: 94),
            help.heightAnchor.constraint(equalToConstant: 26),
            divider.topAnchor.constraint(equalTo: shortcuts.bottomAnchor, constant: 20),
            divider.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            search.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 20),
            search.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            search.heightAnchor.constraint(equalToConstant: 32),
            search.widthAnchor.constraint(greaterThanOrEqualToConstant: 220), searchWidth,
            search.trailingAnchor.constraint(lessThanOrEqualTo: sounds.leadingAnchor, constant: -16),
            sounds.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            sounds.trailingAnchor.constraint(equalTo: speech.leadingAnchor, constant: -10),
            sounds.widthAnchor.constraint(equalToConstant: 90),
            sounds.heightAnchor.constraint(equalToConstant: 32),
            speech.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            speech.trailingAnchor.constraint(equalTo: api.leadingAnchor, constant: -10),
            speech.widthAnchor.constraint(equalToConstant: 112),
            speech.heightAnchor.constraint(equalToConstant: 32),
            api.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            api.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            api.widthAnchor.constraint(equalToConstant: 106),
            api.heightAnchor.constraint(equalToConstant: 32),
            countLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 16),
            countLabel.heightAnchor.constraint(equalToConstant: 18),
            countLabel.widthAnchor.constraint(equalToConstant: 160),
            modelStatus.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 20),
            modelStatus.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            modelStatus.centerYAnchor.constraint(equalTo: countLabel.centerYAnchor),
            modelStatus.heightAnchor.constraint(equalToConstant: 18),
            scroll.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: preferences.topAnchor, constant: -20),
            preferences.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            preferences.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            preferences.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -14),
            preferences.heightAnchor.constraint(equalToConstant: 78),
            enabled.leadingAnchor.constraint(equalTo: preferences.leadingAnchor, constant: 16),
            enabled.trailingAnchor.constraint(lessThanOrEqualTo: preferences.trailingAnchor, constant: -16),
            enabled.topAnchor.constraint(equalTo: preferences.topAnchor, constant: 13),
            enabled.heightAnchor.constraint(equalToConstant: 22),
            privacy.leadingAnchor.constraint(equalTo: preferences.leadingAnchor, constant: 18),
            privacy.trailingAnchor.constraint(equalTo: preferences.trailingAnchor, constant: -16),
            privacy.topAnchor.constraint(equalTo: enabled.bottomAnchor, constant: 5),
            privacy.bottomAnchor.constraint(lessThanOrEqualTo: preferences.bottomAnchor, constant: -10),
            status.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: quit.leadingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            status.heightAnchor.constraint(equalToConstant: 18),
            quit.trailingAnchor.constraint(equalTo: add.trailingAnchor),
            quit.centerYAnchor.constraint(equalTo: status.centerYAnchor),
            quit.widthAnchor.constraint(equalToConstant: 84),
            quit.heightAnchor.constraint(equalToConstant: 24)
        ])
        view.layoutSubtreeIfNeeded()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.contentView?.layoutSubtreeIfNeeded()
        refresh()
        window?.makeFirstResponder(nil)
    }
    func windowDidResize(_ notification: Notification) {
        window?.contentView?.layoutSubtreeIfNeeded()
        refresh()
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        window?.contentView?.layoutSubtreeIfNeeded()
        refresh()
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
    @objc private func showUsageGuide() {
        guard let window else { return }
        let guide = NSAlert()
        guide.messageText = "語音輸入與中翻英"
        guide.informativeText = """
        先點進要輸入的文字框，把游標放好。

        一般輸入
        短按 Fn，聽到提示音即可開始說話；說完再短按 Fn，文字會自動貼入。

        中翻英
        按住 Shift，再短按 Fn 開始，隨即放開 Shift。說完只短按 Fn 結束，會貼入英文。

        中翻英需先到「API 設定」儲存有效金鑰，使用目前選用的雲端服務。第一步可到「語音辨識」選擇本機 Whisper 或 OpenAI GPT Transcribe；雲端選項會上傳錄音並使用 OpenAI 額度。

        若未自動貼入，可按 ⌘V 或 Ctrl+V。快捷鍵請短按，不要長按。
        """
        guide.addButton(withTitle: "知道了")
        guide.beginSheetModal(for: window)
    }
    @objc private func openSoundSettings() { onSoundSettings?() }
    @objc private func openTranscriptionSettings() { onTranscriptionSettings?() }
    @objc private func openAPISettings() { onAPISettings?() }
    @objc private func quitApplication() { onQuit?() }

    func setModelStatus(_ value: String) { modelStatus.stringValue = value }

    private func refresh() {
        grid.subviews.forEach{$0.removeFromSuperview()}
        let query=search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        let entries=settings.entries.filter{query.isEmpty || $0.word.localizedCaseInsensitiveContains(query)}
        displayedIDs=entries.map(\.id)
        countLabel.stringValue=query.isEmpty ? "已儲存 \(settings.entries.count) 個詞" : "找到 \(entries.count) 個詞"
        let width = max(220, scroll.contentView.bounds.width)
        let columns = max(1, min(4, Int((width + 12) / 228)))
        let cardWidth = (width - CGFloat(columns - 1) * 12) / CGFloat(columns)
        let rows = max(1, (entries.count + columns - 1) / columns)
        let height = max(scroll.contentView.bounds.height, CGFloat(rows) * 68 - 12)
        grid.setFrameSize(NSSize(width: width, height: height))
        for (index, entry) in entries.enumerated() {
            let card = DictionaryCardView(frame: NSRect(x: CGFloat(index % columns) * (cardWidth + 12),
                y: CGFloat(index / columns) * 68, width: cardWidth, height: 56))
            let label = NSTextField(labelWithString: entry.word)
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.frame = NSRect(x: 16, y: 17, width: cardWidth - 60, height: 22)
            label.lineBreakMode = .byTruncatingTail
            label.toolTip = entry.word
            card.addSubview(label)
            let remove = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "刪除 \(entry.word)")!,
                                  target: self, action: #selector(removeWord(_:)))
            remove.isBordered = false
            remove.contentTintColor = .secondaryLabelColor
            remove.frame = NSRect(x: cardWidth - 38, y: 15, width: 26, height: 26)
            remove.tag = index
            remove.toolTip = "刪除 \(entry.word)"
            card.addSubview(remove)
            grid.addSubview(card)
        }
        if entries.isEmpty {
            let empty = NSTextField(labelWithString: query.isEmpty ? "加入第一個常用詞，讓辨識更貼近你的用語。" : "沒有符合的詞。")
            empty.frame = NSRect(x: 16, y: max(20, (height - 28) / 2), width: width - 32, height: 28)
            empty.alignment = .center
            empty.textColor = .secondaryLabelColor
            grid.addSubview(empty)
        }
    }
    func controlTextDidChange(_ notification:Notification){refresh()}
    private func persist(_ next:VocabularySettings) -> Bool {
        do {
            let next=try next.validated()
            try onSave?(next); settings=next; refresh()
            status.stringValue="已自動儲存，下一次錄音起生效。"
            return true
        } catch {status.stringValue=error.localizedDescription;return false}
    }
    @objc private func addWord() {
        guard let window else{return}
        let alert=NSAlert()
        alert.messageText="新增單字"
        alert.informativeText="輸入正確寫法即可。多個詞可用逗號分隔。"
        let input=NSTextField(frame:NSRect(x:0,y:0,width:310,height:28))
        let accessory=NSView(frame:NSRect(x:0,y:0,width:398,height:30))
        let pasteTarget=DictionaryPasteTarget(field:input)
        let paste=NSButton(title:"貼上",target:pasteTarget,action:#selector(DictionaryPasteTarget.paste(_:)))
        paste.bezelStyle = .rounded
        paste.frame=NSRect(x:320,y:-1,width:78,height:30)
        accessory.addSubview(input);accessory.addSubview(paste)
        input.placeholderString="例如：Hermes、權限、退出"
        input.setAccessibilityLabel("新增的正確詞")
        alert.accessoryView=accessory
        alert.addButton(withTitle:"新增"); alert.addButton(withTitle:"取消")
        alert.window.initialFirstResponder=input
        alert.beginSheetModal(for:window){[weak self, pasteTarget] response in
            _ = pasteTarget
            guard let self,response == .alertFirstButtonReturn else{return}
            let words=input.stringValue.components(separatedBy:CharacterSet(charactersIn:",，、\n"))
                .map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter{!$0.isEmpty}
            guard !words.isEmpty else{self.status.stringValue="請輸入至少一個正確詞。";return}
            var next=self.settings
            var seen=Set(next.entries.map{$0.word.lowercased()})
            for word in words where seen.insert(word.lowercased()).inserted {
                next.entries.append(VocabularyEntry(word:word))
            }
            _=self.persist(next)
        }
    }
    @objc private func removeWord(_ sender:NSButton) {
        guard displayedIDs.indices.contains(sender.tag) else{return}
        let id=displayedIDs[sender.tag]
        var next=settings; next.entries.removeAll{$0.id==id}
        _=persist(next)
    }
    @objc private func toggleContext() {
        var next=settings; next.contextCorrectionEnabled=enabled.state == .on
        if !persist(next){enabled.state=settings.contextCorrectionEnabled ? .on : .off}
    }
}

private final class DictionaryPasteTarget: NSObject {
    weak var field: NSTextField?
    init(field: NSTextField) { self.field = field }
    @objc func paste(_ sender: Any?) {
        guard let field else { return }
        field.window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.paste(sender)
    }
}

private final class DictionaryGridView: NSView {
    override var isFlipped: Bool { true }
}

private final class DictionaryCardView: NSView {
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.cornerRadius = 12
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
}
