import AppKit
import EdgelessTypeCore

enum CloudAccess {
    static var offlineProbe = false
    private(set) static var offlineProbeRequests = 0
    static var preferences: CloudPreferencesStore {
        CloudPreferencesStore(url: AppPaths.projectRoot().appendingPathComponent("Config/cloud.json"))
    }
    static func store(_ provider: CloudProvider) -> SecretStore {
        SecretStore(locations: SecretLocations.production(projectRoot: AppPaths.projectRoot()), recordName: provider.rawValue)
    }
    static func complete(_ body: ChatBody, purpose: CloudPurpose) throws -> String {
        if offlineProbe { offlineProbeRequests += 1; throw CloudError.invalidRequest }
        let provider = try preferences.load().provider
        let key = String(decoding: try store(provider).readSecret(), as: UTF8.self)
        return try CloudClient.shared.complete(body, provider: provider, purpose: purpose, key: key) { model in
            CloudModelStatus.record(model, provider: provider, purpose: purpose)
        }
    }
}

/// Main-queue, process-local display state. No files, telemetry, or extra requests.
private enum CloudModelStatus {
    static let changed = Notification.Name("edgelesstypeCloudModelDidRespond")
    private struct Reply { let model: String? }
    private static var last: [String: Reply] = [:]
    private static func key(_ provider: CloudProvider, _ purpose: CloudPurpose) -> String {
        provider.rawValue + (purpose == .correction ? ":correction" : ":translation")
    }
    static func record(_ model: String?, provider: CloudProvider, purpose: CloudPurpose) {
        DispatchQueue.main.async {
            last[key(provider, purpose)] = Reply(model: model)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
    static func description(for provider: CloudProvider) -> String {
        let correction = last[key(provider, .correction)]?.model ?? provider.model(for: .correction)
        let translation = last[key(provider, .translation)]?.model ?? provider.model(for: .translation)
        return "校正：\(correction) · 翻譯：\(translation)"
    }
    static func detail(for provider: CloudProvider) -> String {
        [CloudPurpose.correction, .translation].map { purpose in
            let title = purpose == .correction ? "校正" : "翻譯"
            let requested = provider.model(for: purpose)
            guard let reply = last[key(provider, purpose)] else {
                return "\(title)：請求模型 \(requested)；本次啟動尚未收到成功回覆。"
            }
            guard let reported = reply.model else {
                return "\(title)：請求模型 \(requested)；服務商未回傳模型名稱。"
            }
            return "\(title)：請求模型 \(requested)；最近成功回覆 \(reported)。"
        }.joined(separator: "\n")
    }
}

final class APISettingsWindow: NSWindowController, NSWindowDelegate {
    private let preferencesStore: CloudPreferencesStore
    private let keyOnlyProvider: CloudProvider?
    private let keyLocations: SecretLocations
    var onClose: (() -> Void)?
    private func store(_ provider: CloudProvider) -> SecretStore { SecretStore(locations: keyLocations, recordName: provider.rawValue) }
    private let provider = NSPopUpButton()
    private let keyField = NSSecureTextField()
    private let models = NSTextField(wrappingLabelWithString: "")
    private var modelObserver: NSObjectProtocol?
    private let savedStatus = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private var controls: [NSControl] = []
    private var generation = UUID()
    private var selection: CloudProvider { keyOnlyProvider ?? CloudProvider.allCases[max(0, provider.indexOfSelectedItem)] }

    init(preferencesStore: CloudPreferencesStore = CloudAccess.preferences,
         keyLocations: SecretLocations = .production(projectRoot: AppPaths.projectRoot()),
         keyOnlyProvider: CloudProvider? = nil) {
        self.preferencesStore = preferencesStore
        self.keyOnlyProvider = keyOnlyProvider
        self.keyLocations = keyLocations
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 455),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = keyOnlyProvider == nil ? "edgelesstype — API 設定" : "edgelesstype — OpenAI 金鑰"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        if let chosen = keyOnlyProvider ?? (try? preferencesStore.load().provider),
           let index = CloudProvider.allCases.firstIndex(of: chosen) { provider.selectItem(at: index) }
        modelObserver = NotificationCenter.default.addObserver(forName: CloudModelStatus.changed, object: nil, queue: .main) { [weak self] _ in
            self?.refreshModels()
        }
        provider.isEnabled = keyOnlyProvider == nil
        changed(); window.center()
    }
    deinit { if let modelObserver { NotificationCenter.default.removeObserver(modelObserver) } }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        guard let view = window?.contentView else { return }
        func label(_ text: String, _ frame: NSRect, bold: Bool = false) {
            let field = NSTextField(wrappingLabelWithString: text); field.frame = frame
            if bold { field.font = .boldSystemFont(ofSize: 23) }
            view.addSubview(field)
        }
        label("API 設定", NSRect(x: 26, y: 400, width: 500, height: 34), bold: true)
        label(keyOnlyProvider == nil ? "選一家服務商，儲存自己的 API 金鑰即可。" : "儲存 OpenAI 語音辨識金鑰；不改變文字校正服務商。", NSRect(x: 26, y: 368, width: 550, height: 24))
        provider.frame = NSRect(x: 26, y: 321, width: 270, height: 32)
        provider.addItems(withTitles: CloudProvider.allCases.map(\.title))
        provider.target = self; provider.action = #selector(changed)
        provider.setAccessibilityLabel("API 服務商")
        view.addSubview(provider); controls.append(provider)
        addButton("取得 API 金鑰", NSRect(x: 411, y: 321, width: 170, height: 32), #selector(openKeyPage))
        models.frame = NSRect(x: 26, y: 284, width: 550, height: 29); models.textColor = .secondaryLabelColor
        view.addSubview(models)
        models.font = .systemFont(ofSize: 12)
        savedStatus.frame = NSRect(x: 26, y: 252, width: 550, height: 24); view.addSubview(savedStatus)
        keyField.frame = NSRect(x: 26, y: 207, width: 465, height: 32)
        keyField.placeholderString = "貼上新金鑰；留白會沿用已儲存的金鑰"
        keyField.setAccessibilityLabel("API 金鑰")
        view.addSubview(keyField); controls.append(keyField)
        addButton("貼上", NSRect(x: 500, y: 205, width: 81, height: 34), #selector(pasteKey))
        addButton(keyOnlyProvider == nil ? "儲存並使用" : "儲存金鑰", NSRect(x: 26, y: 153, width: 167, height: 35), #selector(save))
        if keyOnlyProvider == nil { addButton("測試連線", NSRect(x: 219, y: 153, width: 167, height: 35), #selector(test)) }
        addButton("刪除金鑰", NSRect(x: 413, y: 153, width: 167, height: 35), #selector(deleteKey))
        label("金鑰加密保存在本機，不會顯示原文。各家金鑰分開保存。\n本機 Whisper 不上傳錄音；選用雲端辨識才傳送音訊至 OpenAI。",
              NSRect(x: 26, y: 84, width: 550, height: 55))
        status.frame = NSRect(x: 26, y: 18, width: 550, height: 56)
        status.textColor = .secondaryLabelColor; view.addSubview(status)
    }
    private func addButton(_ title: String, _ frame: NSRect, _ action: Selector) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded; button.frame = frame
        window?.contentView?.addSubview(button); controls.append(button)
    }
    @objc private func changed() {
        generation = UUID(); keyField.stringValue = ""; status.stringValue = ""
        refreshModels()
        refreshStatus()
    }
    private func refreshModels() {
        models.stringValue = keyOnlyProvider == nil ? CloudModelStatus.description(for: selection) : "語音辨識：" + OpenAITranscriptionWire.model
        models.toolTip = keyOnlyProvider == nil ? CloudModelStatus.detail(for: selection) : "與文字校正共用 OpenAI 金鑰，辨識方式需另外在語音辨識設定選擇。"
    }
    private func refreshStatus() {
        let exists = (try? store(selection).verify()) == true
        let active = (try? preferencesStore.load().provider) == selection
        savedStatus.stringValue = (exists ? "已儲存金鑰" : "尚未儲存金鑰") + (keyOnlyProvider != nil ? " · OpenAI 共用金鑰" : (active ? " · 目前選用" : " · 尚未選用"))
    }
    @objc private func openKeyPage() { NSWorkspace.shared.open(selection.keyPage) }
    @objc private func pasteKey() { keyField.stringValue = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    @objc private func save() {
        do {
            let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                guard !key.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else { throw CloudError.invalidKey }
                try store(selection).save(secret: Data(key.utf8))
            } else if (try? store(selection).verify()) != true { throw CloudError.missingKey }
            if keyOnlyProvider == nil { try preferencesStore.save(CloudPreferences(provider: selection)) }
            keyField.stringValue = ""; refreshStatus()
            status.stringValue = keyOnlyProvider == nil ? "已儲存並選用 \(selection.title)。可按「測試連線」確認。" : "OpenAI 金鑰已儲存。文字校正服務商未變更。"
        } catch { show(error) }
    }
    @objc private func deleteKey() {
        let selected = selection
        let alert = NSAlert()
        alert.messageText = "刪除 \(selected.title) 的金鑰？"
        alert.informativeText = "只移除這家服務商的本機金鑰紀錄，其他服務商不受影響。"
        alert.addButton(withTitle: "刪除"); alert.addButton(withTitle: "取消")
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .alertFirstButtonReturn else { return }
            do {
                try store(selected).delete()
                self.keyField.stringValue = ""; self.refreshStatus()
                self.status.stringValue = "已刪除 \(selected.title) 金鑰。本機辨識仍可使用。"
            } catch { self.show(error) }
        }
    }
    @objc private func test() {
        let selected = selection
        let typed = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String
        do { key = typed.isEmpty ? String(decoding: try store(selected).readSecret(), as: UTF8.self) : typed }
        catch { show(CloudError.missingKey); return }
        generation = UUID(); let token = generation
        controls.forEach { $0.isEnabled = false }; status.stringValue = "正在測試 \(selected.title)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let body = ChatBody(model: selected.model(for: .correction), timeoutSeconds: 20, reasoningEffort: nil,
                                system: "Reply with OK only.", user: "Connection test.")
            let result = Result {
                try CloudClient.shared.complete(body, provider: selected, purpose: .correction, key: key) { model in
                    CloudModelStatus.record(model, provider: selected, purpose: .correction)
                }
            }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.controls.forEach { $0.isEnabled = true }; self.provider.isEnabled = self.keyOnlyProvider == nil
                switch result {
                case .success: self.status.stringValue = "\(selected.title) 連線成功。" + (typed.isEmpty ? "" : "這把新金鑰尚未儲存，請按「儲存並使用」。")
                case .failure(let error): self.show(error)
                }
            }
        }
    }
    private func show(_ error: Error) { status.stringValue = (error as? CloudError)?.errorDescription ?? "無法讀寫金鑰。若從其他 Mac 搬來，請確認金鑰表與密文配對；原檔未覆寫。" }
    func windowWillClose(_ notification: Notification) { generation = UUID(); keyField.stringValue = ""; controls.forEach { $0.isEnabled = true }; provider.isEnabled = keyOnlyProvider == nil; onClose?() }
}
