#if !os(macOS) || !arch(arm64)
#error("edgelesstype supports only Apple silicon M-series Macs.")
#endif
import AppKit
import AVFoundation
import Darwin
import Foundation
import Network
import EdgelessTypeCore

@_silgen_name("CGRequestListenEventAccess")
func CGRequestListenEventAccess() -> Bool

@_silgen_name("CGPreflightListenEventAccess")
func CGPreflightListenEventAccess() -> Bool

struct AppConfig: Codable {
    var whisperCLI: String
    var modelPath: String
    var ffmpegPath: String
    var audioDevice: String
    var language: String
    var threads: Int
    var tapMaxSeconds: Double
    var polish: PolishConfig
    var translate: TranslateConfig
    var terms: [String]
    var residentSpeech: ResidentSpeechConfig?

    enum CodingKeys: String, CodingKey {
        case whisperCLI, modelPath, ffmpegPath, audioDevice, language, threads, tapMaxSeconds, polish, translate, terms, residentSpeech
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        whisperCLI = try box.decode(String.self, forKey: .whisperCLI)
        modelPath = try box.decode(String.self, forKey: .modelPath)
        ffmpegPath = try box.decode(String.self, forKey: .ffmpegPath)
        audioDevice = try box.decode(String.self, forKey: .audioDevice)
        language = try box.decode(String.self, forKey: .language)
        threads = try box.decode(Int.self, forKey: .threads)
        tapMaxSeconds = try box.decode(Double.self, forKey: .tapMaxSeconds)
        polish = try box.decode(PolishConfig.self, forKey: .polish)
        translate = try box.decode(TranslateConfig.self, forKey: .translate)
        residentSpeech = try box.decodeIfPresent(ResidentSpeechConfig.self, forKey: .residentSpeech)
        terms = try box.decodeIfPresent([String].self, forKey: .terms) ?? ["Hermes"]
    }
}

struct PolishConfig: Codable {
    var enabled: Bool
    var timeoutSeconds: Double
}

struct TranslateConfig: Codable {
    var reasoningEffort: String
    var timeoutSeconds: Double
}

enum AppPaths {
    static var transcriptionStore: TranscriptionPreferencesStore {
        TranscriptionPreferencesStore(url: projectRoot().appendingPathComponent("Config/transcription.json"))
    }

    static var soundSettingsStore: SoundSettingsStore {
        SoundSettingsStore(url: projectRoot().appendingPathComponent("Config/sounds.json"))
    }

    static var vocabularyStore: VocabularyStore {
        VocabularyStore(url: projectRoot().appendingPathComponent("Config/vocabulary.json"))
    }

    static func projectRoot() -> URL {
        let start = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var url = start.deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Config/app.json").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        // Bundle-relative fallback: never embed a developer's source path.
        return start.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func resolve(_ path: String) -> String {
        guard !path.hasPrefix("/") else { return path }
        return projectRoot().appendingPathComponent(path).standardizedFileURL.path
    }

    static var localSettingsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/codex-secrets", isDirectory: true)
    }

    static func loadConfig() throws -> AppConfig {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundled = exe
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/app.json")
        let local = projectRoot().appendingPathComponent("Config/app.json")
        let url = FileManager.default.fileExists(atPath: local.path) ? local : bundled
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
}

enum CLI {
    static func run(_ args: [String]) -> Int32 {
        let command = args.dropFirst().first ?? "help"
        do {
            switch command {
            case "verify-key":
                let store = SecretStore(locations: SecretLocations.production(projectRoot: AppPaths.projectRoot()))
                let ok = try store.verify()
                FileHandle.standardOutput.write(Data((ok ? "金鑰已保存\n" : "尚未保存金鑰\n").utf8))
                return ok ? 0 : 1
            case "set-key":
                try setKey()
                FileHandle.standardOutput.write(Data("已保存。金鑰沒有寫進這個資料夾的明文，也沒有印出來。\n".utf8))
                return 0
            case "delete-key":
                let store = SecretStore(locations: SecretLocations.production(projectRoot: AppPaths.projectRoot()))
                try store.delete()
                FileHandle.standardOutput.write(Data("已刪除這支程式保存的金鑰密文。\n".utf8))
                return 0
            case "transcribe":
                guard args.count >= 3 else {
                    FileHandle.standardError.write(Data("需要一個音檔路徑。\n".utf8))
                    return 2
                }
                let config = try AppPaths.loadConfig()
                let text = try Transcriber(config: config).transcribe(url: URL(fileURLWithPath: args[2]))
                FileHandle.standardOutput.write(Data((text + "\n").utf8))
                return 0
            default:
                FileHandle.standardOutput.write(Data("用法：verify-key、set-key、delete-key、transcribe <音檔>\n".utf8))
                return 2
            }
        } catch {
            FileHandle.standardError.write(Data("沒有完成。沒有印出金鑰。\n".utf8))
            return 1
        }
    }

    static func setKey() throws {
        guard isatty(STDIN_FILENO) == 1 else { throw SecretError.notATerminal }
        FileHandle.standardError.write(Data("貼上金鑰後按 Enter。畫面不會顯示。不要把金鑰貼到聊天裡。\n".utf8))
        let secret = try HiddenInput.read()
        let store = SecretStore(locations: SecretLocations.production(projectRoot: AppPaths.projectRoot()))
        try store.save(secret: Data(secret.utf8))
    }
}

enum HiddenInput {
    static func read() throws -> String {
        var old = termios()
        tcgetattr(STDIN_FILENO, &old)
        var hidden = old
        hidden.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &hidden)
        defer { tcsetattr(STDIN_FILENO, TCSANOW, &old) }
        guard let line = readLine(strippingNewline: true) else { throw SecretError.emptySecret }
        FileHandle.standardError.write(Data("\n".utf8))
        return line
    }
}

struct Transcriber {
    let config: AppConfig
    var vocabulary: VocabularySettings? = nil
    var transcription = TranscriptionPreferences()
    var recordingContext: String?

    func transcribe(url: URL, onProgress: ((Double) -> Void)? = nil, onTimings: ((TranscriptionTransferTimings) -> Void)? = nil, cancellation: ProcessingCancellation? = nil) throws -> String {
        try cancellation?.check()
        if let data = try? Data(contentsOf: url), SpeechContent.isDigitalSilence(data) == true { return "" }
        return try TranscriptionRouter.run(transcription,
            local: { try localTranscribe(url: url, cancellation: cancellation) },
            cloud: { try CloudTranscriptionService.transcribe(url: url, preferences: transcription, terms: vocabulary?.entries.map(\.word) ?? config.terms,
                onProgress: onProgress, onTimings: onTimings, context: recordingContext, cancellation: cancellation) })
    }

    private func localTranscribe(url: URL, cancellation: ProcessingCancellation?) throws -> String {
        try cancellation?.check()
        if config.residentSpeech != nil {
            return try ResidentSpeechEngine.shared.transcribe(url: url, config: config,
                prompt: RecordingContext.prompt(terms: Terms.prompt(terms: vocabulary?.entries.map(\.word) ?? config.terms), context: recordingContext), cancellation: cancellation)
        }
        let vadModel = AppPaths.resolve(SpeechContent.vadModelRelativePath)
        guard FileManager.default.fileExists(atPath: vadModel) else { throw SpeechEngineError.missingSpeechDetector }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AppPaths.resolve(config.whisperCLI))
        process.arguments = [
            "-m", AppPaths.resolve(config.modelPath),
            "-f", url.path,
            "-l", config.language,
            "-t", String(config.threads),
            "-nt", "-np", "--vad", "--vad-model", vadModel,
            "--vad-min-speech-duration-ms", "100", "--vad-speech-pad-ms", "120",
            "--prompt", Terms.prompt(terms: vocabulary?.entries.map(\.word) ?? config.terms)
        ]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let registration = cancellation?.register { if process.isRunning { process.terminate() } }
        defer { cancellation?.unregister(registration) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try cancellation?.check()
        guard process.terminationStatus == 0 else { throw SpeechEngineError.invalidResponse }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

final class HotkeyMonitor {
    var onTap: ((TapKind) -> Void)?
    var onPasteKey: ((Bool, Bool) -> Bool)?
    var tapMax: TimeInterval = Hotkey.defaultTapMax
    private var tap: CFMachPort?
    private var downAt: Date?
    private var shiftDuring = false
    private var sawKeyDown = false
    private let fnCode: Int64 = 63
    var mode = "none"

    func install(listenOnly: Bool = false) -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: listenOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let consume = monitor.handle(type: type, event: event)
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        mode = listenOnly ? "listen" : "active"
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown, code == 9 {
            let command = event.flags.contains(.maskCommand)
            let control = event.flags.contains(.maskControl)
            if command || control {
                let fromUs = event.getIntegerValueField(.eventSourceUserData) == 7941
                return self.onPasteKey?(control && !command, fromUs) ?? false
            }
            return false
        }
        guard code == fnCode else { return false }
        let shift = event.flags.contains(.maskShift)
        switch type {
        case .keyDown:
            if downAt == nil {
                downAt = Date()
                shiftDuring = shift
                sawKeyDown = true
            } else if shift {
                shiftDuring = true
            }
        case .keyUp:
            finish(shiftNow: shift)
        case .flagsChanged:
            let fnOn = event.flags.contains(.maskSecondaryFn)
            if fnOn && downAt == nil {
                downAt = Date()
                shiftDuring = shift
                sawKeyDown = false
            } else if fnOn && shift {
                shiftDuring = true
            } else if !fnOn && downAt != nil {
                finish(shiftNow: shift)
            }
        default:
            break
        }
        return true
    }

    private func finish(shiftNow: Bool) {
        guard let downAt else { return }
        if shiftNow { shiftDuring = true }
        let gesture = FnGesture(duration: Date().timeIntervalSince(downAt), shiftDuring: shiftDuring)
        self.downAt = nil
        self.shiftDuring = false
        self.sawKeyDown = false
        guard let kind = Hotkey.classify(gesture, maxTap: tapMax) else { return }
        DispatchQueue.main.async { [onTap] in onTap?(kind) }
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = RecordChrome()
    private let notices = NoticePanel()
    private let paster = Paster()
    private lazy var soundPlayer = SoundPlayer(store: AppPaths.soundSettingsStore)
    private var recordingSoundPreset: SoundPreset?
    private var pendingRecordingStart = PendingRecordingStart()
    private var soundEditor: SoundSettingsWindow?
    private var monitor: HotkeyMonitor?
    private var recorder: Recorder?
    private var config: AppConfig?
    private var session = Session.idle
    private var busy = false
    private var currentProcessing: ProcessingJob?
    private var contextCapture: RecordingContext?
    private var explained = false
    private var askedListen = false
    private var toldMissing = false
    private var retry: Timer?
    private var recordingURL: URL?
    private var targetPID: pid_t?
    private var startedAt: Date?
    private var recordingVocabulary = VocabularySettings()
    private var apiEditor: APISettingsWindow?
    private var transcriptionKeyEditors: [CloudProvider: APISettingsWindow] = [:]
    private var transcriptionEditor: TranscriptionSettingsWindow?
    private var recordingTranscription = TranscriptionPreferences()
    private var transcriptionBackend: TranscriptionBackend {
        (try? AppPaths.transcriptionStore.load().backend) ?? .localWhisper
    }
    private var vocabularyEditor: VocabularyWindow?
    private var pendingTiming: DictationTiming?
    private struct RetryContext {
        var text: String
        var settings: VocabularySettings
        var config: AppConfig
    }
    private var retryContext: RetryContext?
    private var correctionDegraded = false
    private let pathMonitor = NWPathMonitor()
    private let pathLock = NSLock()
    private var pathSatisfiedValue = true
    private var warmedAt: [String: Date] = [:]
    private var pathSatisfied: Bool { pathLock.lock(); defer { pathLock.unlock() }; return pathSatisfiedValue }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setStatus(AppIdentity.displayName)
        installApplicationMenu()
        requestAccessibility()
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if self.paster.isOffering {
                self.paster.cancelOffer()
                self.panel.hide()
                return
            }
            self.cancel()
        }
        panel.onConfirm = { [weak self] in self?.finish() }
        panel.onSkipCloud = { [weak self] in self?.currentProcessing?.cancellation.skipCloud() }
        panel.onDegraded = { [weak self] outcome in
            guard let self, let notice = OutputPolicy.correctionNotice(outcome: outcome) else { return }
            self.correctionDegraded = true
            self.setStatus(AppIdentity.displayName)
            self.notices.showDegraded(notice)
        }
        panel.onFailure = { [weak self] title, detail in
            self?.notices.showFailure(title: title, detail: detail)
        }
        notices.onRetry = { [weak self] in self?.retryLastCorrection() }
        notices.onCopy = { [weak self] in self?.copyRetryText() }
        notices.onOpenSettings = { [weak self] in self?.showAPISettings() }
        notices.onDismissed = { [weak self] in self?.retryContext = nil }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.pathLock.lock()
            self.pathSatisfiedValue = path.status == .satisfied
            self.pathLock.unlock()
        }
        pathMonitor.start(queue: DispatchQueue(label: "edgelesstype.network"))
        paster.onDismiss = { [weak self] in self?.panel.dismissPending(); self?.finishTiming() }
        rebuildMenu()
        explainIfNeeded {
            self.installKeys()
        }
    }

    private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func installApplicationMenu() {
        let bar = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: AppIdentity.displayName)
        let dictionary = applicationMenu.addItem(withTitle: "字典…", action: #selector(showVocabulary), keyEquivalent: ",")
        dictionary.target = self
        let speech = applicationMenu.addItem(withTitle: "語音辨識…", action: #selector(showTranscriptionSettings), keyEquivalent: "")
        speech.target = self
        let api = applicationMenu.addItem(withTitle: "API 設定…", action: #selector(showAPISettings), keyEquivalent: "")
        api.target = self
        let sounds = applicationMenu.addItem(withTitle: "提示音…", action: #selector(showSoundSettings), keyEquivalent: "")
        sounds.target = self
        applicationMenu.addItem(.separator())
        let quit = applicationMenu.addItem(withTitle: "退出 \(AppIdentity.displayName)", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        applicationItem.submenu = applicationMenu
        bar.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "編輯")
        for (title, action, key) in [("復原", "undo:", "z"), ("剪下", "cut:", "x"),
                                     ("複製", "copy:", "c"), ("貼上", "paste:", "v"),
                                     ("全選", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "短按 Fn：聽寫開始／結束", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "短按 Fn+Shift 開始翻譯，單按 Fn 結束", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "校正等太久：再按 Fn 先貼原文", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let explain = menu.addItem(withTitle: "查看權限說明", action: #selector(showExplain), keyEquivalent: "")
        explain.target = self
        let enable = menu.addItem(withTitle: "啟用 Fn 鍵", action: #selector(enableKeys), keyEquivalent: "")
        enable.target = self
        let polish = menu.addItem(
            withTitle: (config?.polish.enabled ?? false) ? "潤飾：開" : "潤飾：關（預設）",
            action: #selector(togglePolish),
            keyEquivalent: ""
        )
        polish.target = self
        let speech = menu.addItem(withTitle: "語音辨識：" + transcriptionBackend.title + "…", action: #selector(showTranscriptionSettings), keyEquivalent: "")
        speech.target = self
        let api = menu.addItem(withTitle: "API 設定…", action: #selector(showAPISettings), keyEquivalent: "")
        api.target = self
        let sounds = menu.addItem(withTitle: "提示音…", action: #selector(showSoundSettings), keyEquivalent: "")
        sounds.target = self
        let vocabulary = menu.addItem(withTitle: "字典…", action: #selector(showVocabulary), keyEquivalent: "")
        vocabulary.target = self
        if transcriptionBackend == .localWhisper, let resident = config?.residentSpeech {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Metal GPU 常駐辨識", action: nil, keyEquivalent: "")
            for (key, title) in [("turbo", "Large-v3 Turbo"), ("small", "Small")] {
                let item = menu.addItem(withTitle: title, action: #selector(selectSpeechModel(_:)), keyEquivalent: "")
                item.representedObject = key
                item.state = resident.selectedModel == key ? .on : .off
                item.target = self
            }
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "結束", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        status.menu = menu
    }

    @objc private func showExplain() {
        explainIfNeeded(then: nil)
    }

    @objc private func enableKeys() {
        explainIfNeeded {
            self.installKeys()
        }
    }

    @objc private func togglePolish() {
        guard var config else { return }
        config.polish.enabled.toggle()
        self.config = config
        rebuildMenu()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showVocabulary()
        return true
    }

    @objc private func showSoundSettings() {
        if soundEditor == nil { soundEditor = SoundSettingsWindow(player: soundPlayer) }
        soundEditor?.refresh()
        soundEditor?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showTranscriptionSettings() {
        guard session == .idle, !busy else { panel.showMessage(TranscriptionError.busy.errorDescription!); return }
        if transcriptionEditor == nil {
            let editor = TranscriptionSettingsWindow(store: AppPaths.transcriptionStore)
            editor.onKey = { [weak self] provider in
                guard let self else { return }
                if self.transcriptionKeyEditors[provider] == nil { self.transcriptionKeyEditors[provider] = APISettingsWindow(keyOnlyProvider: provider) }
                self.transcriptionKeyEditors[provider]?.showWindow(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            editor.onSave = { [weak self] preferences in
                guard let self, self.session == .idle, !self.busy else { throw TranscriptionError.busy }
                try AppPaths.transcriptionStore.save(preferences)
                self.rebuildMenu()
                if preferences.backend == .localWhisper { self.warmSpeechEngine() }
                else {
                    ResidentSpeechEngine.shared.shutdown()
                    self.vocabularyEditor?.setModelStatus(preferences.backend.statusTitle)
                }
            }
            transcriptionEditor = editor
        }
        transcriptionEditor?.refresh()
        transcriptionEditor?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAPISettings() {
        if apiEditor == nil { apiEditor = APISettingsWindow() }
        apiEditor?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showVocabulary() {
        guard session == .idle, !busy else { return }
        do {
            let settings = try AppPaths.vocabularyStore.load(fallbackTerms: config?.terms ?? [])
            if vocabularyEditor == nil {
                let editor = VocabularyWindow(settings: settings)
                editor.onSave = { settings in try AppPaths.vocabularyStore.save(settings) }
                editor.onSoundSettings = { [weak self] in self?.showSoundSettings() }
                editor.onAPISettings = { [weak self] in self?.showAPISettings() }
                editor.onTranscriptionSettings = { [weak self] in self?.showTranscriptionSettings() }
                editor.onQuit = { [weak self] in self?.quit() }
                vocabularyEditor = editor
            }
            if transcriptionBackend.isCloud {
                vocabularyEditor?.setModelStatus(transcriptionBackend.statusTitle)
            } else if let resident = config?.residentSpeech {
                let info = ResidentSpeechEngine.shared.diagnostics
                vocabularyEditor?.setModelStatus(info.ready && info.metal && info.pid != nil
                    ? "\(resident.displayName) · Metal GPU · 已常駐" : "正在預載 \(resident.displayName)…")
            }
            vocabularyEditor?.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert()
            alert.messageText = "無法讀取詞彙設定"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func selectSpeechModel(_ sender: NSMenuItem) {
        guard session == .idle, !busy, var config,
              let selected = sender.representedObject as? String,
              config.residentSpeech != nil else { return }
        config.residentSpeech?.selectedModel = selected
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(config).write(to: AppPaths.projectRoot().appendingPathComponent("Config/app.json"), options: .atomic)
            self.config = config
            rebuildMenu()
            warmSpeechEngine()
        } catch { panel.showMessage("模型設定沒有儲存成功") }
    }

    private func warmSpeechEngine() {
        guard transcriptionBackend == .localWhisper else {
            vocabularyEditor?.setModelStatus(transcriptionBackend.statusTitle)
            return
        }
        guard let config, let resident = config.residentSpeech else { return }
        status.button?.title = "載入"
        vocabularyEditor?.setModelStatus("正在預載 \(resident.displayName)…")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try ResidentSpeechEngine.shared.warmUp(config: config)
                DispatchQueue.main.async {
                    guard self.transcriptionBackend == .localWhisper else { return }
                    if !self.busy && self.session == .idle { self.setStatus(AppIdentity.displayName) }
                    self.vocabularyEditor?.setModelStatus("\(resident.displayName) · Metal GPU · 已常駐")
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.transcriptionBackend == .localWhisper else { return }
                    self.status.button?.title = "模型未就緒"
                    self.vocabularyEditor?.setModelStatus((error as? SpeechEngineError)?.errorDescription ?? "模型載入失敗，可從語音選單切換 Small 後重試。")
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        contextCapture?.discard(); contextCapture = nil
        currentProcessing?.cancellation.cancel()
        pendingRecordingStart.cancel()
        soundPlayer.cancelPreview()
        ResidentSpeechEngine.shared.shutdown()
        cleanup(recorder?.stop())
        retry?.invalidate()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func explainIfNeeded(then next: (() -> Void)?) {
        if explained || FileManager.default.fileExists(atPath: Self.explainedMarker.path) {
            explained = true
            next?()
            return
        }
        let alert = NSAlert()
        alert.messageText = "先看這段，再決定要不要授權"
        alert.informativeText = Promise.beforePermission
        alert.addButton(withTitle: "我知道了")
        alert.addButton(withTitle: "先不要")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            explained = true
            try? FileManager.default.createDirectory(at: AppPaths.localSettingsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? Data("ok".utf8).write(to: Self.explainedMarker)
            next?()
        }
    }

    private static var explainedMarker: URL {
        AppPaths.localSettingsDirectory.appendingPathComponent("edgelesstype-explained")
    }

    private func installKeys() {
        if monitor != nil { return }
        do {
            config = try AppPaths.loadConfig()
        } catch {
            panel.showMessage("讀不到設定")
            return
        }
        if !askedListen {
            askedListen = true
            _ = CGRequestListenEventAccess()
        }
        let allowed = CGPreflightListenEventAccess()
        let active = HotkeyMonitor()
        active.tapMax = config?.tapMaxSeconds ?? Hotkey.defaultTapMax
        active.onTap = { [weak self] kind in self?.handle(kind) }
        active.onPasteKey = { [weak self] controlOnly, fromUs in
            guard let self, !fromUs else { return false }
            let handled = self.paster.notePasteKey(controlOnly: controlOnly, fromUs: false)
            if handled { self.pendingTiming?.manualPaste = true }
            return handled
        }
        let listening = allowed && (active.install() || active.install(listenOnly: true))
        try? Data("allowed=\(allowed) mode=\(active.mode) listening=\(listening)\n".utf8).write(to: AppPaths.localSettingsDirectory.appendingPathComponent("edgelesstype-status.txt"))
        if listening {
            self.monitor = active
            rebuildMenu()
            warmSpeechEngine()
            retry?.invalidate()
            retry = nil
            NSApp.setActivationPolicy(.regular)
            setStatus(AppIdentity.displayName)
            panel.showMessage("Fn 已啟用")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.panel.hide() }
        } else {
            status.button?.title = "語音·未授權"
            panel.showMessage("Fn 還沒進來。請打開輸入監控裡的「\(AppIdentity.displayName)」。")
            if !toldMissing {
                toldMissing = true
                let alert = NSAlert()
                alert.messageText = "還沒有輸入監控"
                alert.informativeText = "系統設定要開的是「輸入監控」，不是輔助使用。把「\(AppIdentity.displayName)」打開，Fn 才進得來。本機 Whisper 不上傳錄音；只有選用雲端辨識時才傳送至 OpenAI。"
                alert.addButton(withTitle: "打開輸入監控")
                alert.addButton(withTitle: "先不要")
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: PermissionPane.inputMonitoring)!)
                }
            }
            if retry == nil {
                retry = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                    self?.installKeys()
                }
            }
        }
    }

    private func handle(_ kind: TapKind) {
        // Keep the visible cancel control available while processing.
        // Once the rough-paste button shows, a lone Fn tap presses it too.
        if busy {
            if kind == .fn, panel.offersSkipCloud { currentProcessing?.cancellation.skipCloud() }
            return
        }
        let action = Hotkey.decide(session: session, tap: kind)
        switch action {
        case .startDictation:
            begin(.dictation)
        case .startTranslation:
            begin(.translation)
        case .stopDictation, .stopTranslation:
            finish()
        case .ignore:
            panel.showMessage("結束時只按 Fn，不要按著 Shift")
        }
    }

    private func begin(_ mode: Session) {
        guard let config else { return }
        do { recordingTranscription = try AppPaths.transcriptionStore.load() }
        catch { notices.showFailure(title: "無法開始錄音", detail: "語音辨識設定無法讀取，請重新選擇並儲存。"); return }
        pendingTiming = nil
        paster.cancelOffer()
        notices.hide()
        // Read for each recording; user edits need no app restart. A broken
        // vocabulary file must not turn on cloud processing or be overwritten.
        recordingVocabulary = (try? AppPaths.vocabularyStore.load(fallbackTerms: config.terms))
            ?? VocabularySettings(entries: config.terms.map { VocabularyEntry(word: $0) })
        prewarmCorrectionConnection()
        prewarmAudioConnection()
        // Capture the destination at the Fn gesture, before any asynchronous cue.
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        contextCapture?.discard()
        contextCapture = nil
        if recordingTranscription.capturesRecordingContext, let pid = targetPID, pid != getpid() {
            let capture = RecordingContext()
            contextCapture = capture
            RecordingContextReader.capture(pid: pid, into: capture)
        }
        session = mode
        startedAt = nil
        soundPlayer.cancelPreview()
        recordingSoundPreset = soundPlayer.preset
        let token = pendingRecordingStart.schedule()
        panel.showMessage("正在開啟麥克風…")
        status.button?.title = "準備錄音"
        let launch = { [weak self] in
            guard let self, self.pendingRecordingStart.contains(token), self.session == mode else { return }
            let recorder = Recorder()
            self.recorder = recorder
            let fail = { [weak self, weak recorder] in
                guard let self, let recorder, self.recorder === recorder else { return }
                self.cancel()
                self.panel.showMessage("錄音中斷或麥克風未就緒，請檢查麥克風權限與輸入裝置，再按 Fn 重試。")
            }
            do {
                self.recordingURL = try recorder.start(cueURL: self.soundPlayer.cueURL(.start, preset: self.recordingSoundPreset), onReady: { [weak self, weak recorder] in
                    guard let self, let recorder, self.recorder === recorder,
                          self.pendingRecordingStart.consume(token), self.session == mode else { return false }
                    self.startedAt = Date()
                    self.status.button?.title = mode == .translation ? "翻譯" : "聽寫"
                    self.panel.showRecording()
                    return true
                }, onFailure: fail)
            } catch { fail() }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: launch()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.pendingRecordingStart.contains(token), self.session == mode else { return }
                    if allowed { launch() }
                    else { self.cancel(); self.panel.showMessage("請在系統設定允許 \(AppIdentity.displayName) 使用麥克風。") }
                }
            }
        default:
            cancel()
            panel.showMessage("請在系統設定允許 \(AppIdentity.displayName) 使用麥克風。")
        }
    }

    private func cancel() {
        contextCapture?.discard(); contextCapture = nil
        currentProcessing?.cancellation.cancel()
        currentProcessing = nil
        pendingRecordingStart.cancel()
        recordingSoundPreset = nil
        soundPlayer.cancelPreview()
        pendingTiming = nil
        session = .idle
        let url = recorder?.stop()
        recorder = nil
        startedAt = nil
        cleanup(url)
        busy = false
        setStatus(AppIdentity.displayName)
        panel.hide()
    }

    private func finish() {
        guard session != .idle else { return }
        let mode = session
        var timing = DictationTiming(startedUptime: DispatchTime.now().uptimeNanoseconds,
            mode: mode == .translation ? "translation" : "dictation",
            model: recordingTranscription.backend.cloudModel ?? (config?.residentSpeech?.displayName ?? "Small CPU"))
        session = .idle
        pendingRecordingStart.cancel()
        soundPlayer.cancelPreview()
        busy = true
        let url = recorder?.stop()
        recorder = nil
        // Close native microphone capture before playing the completion cue.
        soundPlayer.play(.stop, preset: recordingSoundPreset)
        recordingSoundPreset = nil
        let neverReady = startedAt == nil
        startedAt = nil
        guard let url, !neverReady else {
            contextCapture?.discard(); contextCapture = nil
            cleanup(url)
            busy = false
            setStatus(AppIdentity.displayName)
            panel.hide()
            return
        }
        timing.recordingStopSeconds = timing.elapsed()
        let startedTiming = timing
        status.button?.title = mode == .translation ? "譯中" : "轉寫"
        panel.showWorking(recordingTranscription.backend.isCloud ? .uploading : .recognizing)
        launchProcessing(url: url, mode: mode, timing: startedTiming)
    }

    // Explicit development probe: synthetic PCM only; cloud access is blocked.
    func runSilenceProbe(source: URL, requireDigitalSilence: Bool = true) -> Int32 {
        guard let audio = try? Data(contentsOf: source), SpeechContent.isDigitalSilence(audio) != nil,
              (!requireDigitalSilence || SpeechContent.isDigitalSilence(audio) == true),
              let loaded = try? AppPaths.loadConfig() else { print("silent-fixture-required"); return 2 }
        config = loaded
        CloudAccess.offlineProbe = true
        recordingVocabulary = VocabularySettings(contextCorrectionEnabled: true)
        if !requireDigitalSilence {
            guard let config, (try? Transcriber(config: config).transcribe(url: source)) == "" else {
                print("non-speech-fixture-rejected-before-paste"); return 1
            }
        }
        let boardCount = NSPasteboard.general.changeCount
        for mode: Session in [.dictation, .translation] {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("edgelesstype-silence-" + UUID().uuidString + ".wav")
            do { try audio.write(to: temp) } catch { return 2 }
            busy = true; panel.showWorking()
            let timing = DictationTiming(startedUptime: DispatchTime.now().uptimeNanoseconds, mode: "silence-test", model: "test")
            launchProcessing(url: temp, mode: mode, timing: timing)
            let deadline = Date().addingTimeInterval(5)
            while busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            guard !busy, !panel.isVisible, !paster.isOffering, NSPasteboard.general.changeCount == boardCount else {
                panel.hide(); print("silence-check-failed"); return 1
            }
        }
        for punctuation in [".", "。", "…", " "] { paster.offer(punctuation, into: nil) }
        let ok = !paster.isOffering && NSPasteboard.general.changeCount == boardCount && CloudAccess.offlineProbeRequests == 0
        print("silentPanelHidden=true clipboardUnchanged=\(ok) punctuationNotOffered=\(!paster.isOffering) cloudRequests=\(CloudAccess.offlineProbeRequests)")
        return ok ? 0 : 1
    }

    private struct ProcessingJob {
        let cancellation = ProcessingCancellation()
        let config: AppConfig
        let vocabulary: VocabularySettings
        let transcription: TranscriptionPreferences
        let targetPID: pid_t?
        let context: String?
    }

    private func launchProcessing(url: URL, mode: Session, timing: DictationTiming) {
        guard let config else { contextCapture?.discard(); contextCapture = nil; cleanup(url); busy = false; panel.hide(); return }
        let job = ProcessingJob(config: config, vocabulary: recordingVocabulary,
                                transcription: recordingTranscription, targetPID: targetPID, context: contextCapture?.take())
        contextCapture = nil
        currentProcessing = job
        DispatchQueue.global(qos: .userInitiated).async {
            self.process(url: url, mode: mode, timing: timing, job: job)
        }
    }

    private func updateUI(for job: ProcessingJob, _ update: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard self.currentProcessing?.cancellation === job.cancellation,
                  !job.cancellation.isCancelled else { return }
            update()
        }
    }

    private func process(url: URL, mode: Session, timing: DictationTiming, job: ProcessingJob) {
        let cancellation = job.cancellation
        let recordingVocabulary = job.vocabulary
        let recordingTranscription = job.transcription
        let config = job.config
        var timing = timing
        let speechStarted = DispatchTime.now().uptimeNanoseconds
        defer {
            cleanup(url)
            updateUI(for: job) {
                self.busy = false
                self.currentProcessing = nil
                self.setStatus(AppIdentity.displayName)
            }
        }
        guard !cancellation.isCancelled else { return }
        let transcript: String
        do {
            transcript = try OutputPolicy.traditional(Transcriber(config: config, vocabulary: recordingVocabulary, transcription: recordingTranscription, recordingContext: job.context).transcribe(url: url,
                onProgress: { fraction in
                    self.updateUI(for: job) { self.panel.showWorking(fraction >= 1 ? .recognizing : .uploading, progress: fraction) }
                }, onTimings: { timing.audioTransfer = $0 }, cancellation: cancellation))
        } catch {
            guard !cancellation.isCancelled else { return }
            let reason = (error as? TranscriptionError)?.errorDescription ?? (error as? CloudError)?.errorDescription
                ?? (error as? SpeechEngineError)?.errorDescription ?? (error as? OutputConversionError)?.errorDescription ?? "轉寫失敗，沒有貼上。"
            updateUI(for: job) { self.panel.hide(); self.notices.showFailure(title: "語音辨識未完成", detail: reason) }
            return
        }
        guard !cancellation.isCancelled else { return }
        timing.recognitionSeconds = Double(DispatchTime.now().uptimeNanoseconds - speechStarted)/1e9
        guard SpeechContent.hasWords(transcript) else {
            updateUI(for: job) { self.panel.hide() }
            return
        }
        let correctionStarted = DispatchTime.now().uptimeNanoseconds
        let corrected: String
        if recordingTranscription.backend.mergesCorrection {
            // The audio request already returned corrected text; no second cloud round trip.
            timing.correctionProvider = recordingTranscription.backend.cloudProvider?.rawValue
            timing.correctionOutcome = "merged"
            corrected = transcript
        } else if ProcessingPlan.separateCorrection(mode: mode, enabled: recordingVocabulary.contextCorrectionEnabled) && !transcript.isEmpty {
            updateUI(for: job) { self.status.button?.title = "校正"; self.panel.showWorking(.correcting) }
            timing.correctionProvider = (try? CloudAccess.preferences.load().provider.rawValue)
            if !pathSatisfied {
                let decision = CloudRecovery.offline(transcript: transcript)
                timing.correctionOutcome = decision.outcome
                corrected = decision.text
            } else {
                do {
                    var transfer: TranscriptionTransferTimings?
                    corrected = try ContextCorrectionService.correct(transcript, settings: recordingVocabulary, config: config, cancellation: cancellation) { transfer = $0 }
                    timing.correctionTransfer = transfer
                    timing.correctionOutcome = corrected == transcript ? "unchanged" : "corrected"
                } catch {
                    let decision = CloudRecovery.correctionFallback(skipped: cancellation.didSkipCloud, cancelled: cancellation.isCancelled, failure: error as? CloudError, transcript: transcript)
                    guard decision.pasteOnce else { return }
                    timing.correctionOutcome = decision.outcome
                    if decision.outcome != "skipped" { timing.saveCorrectionFailure() }
                    corrected = decision.text
                }
            }
        } else {
            corrected = transcript
        }
        guard !cancellation.isCancelled else { return }
        timing.correctionSeconds = Double(DispatchTime.now().uptimeNanoseconds - correctionStarted)/1e9
        let plan = Policy.plan(mode: mode, transcript: corrected, polishEnabled: config.polish.enabled,
            acceptModelText: OutputPolicy.acceptsModelText(outcome: timing.correctionOutcome))
        switch plan {
        case .drop:
            updateUI(for: job) { self.panel.hide() }
        case .pasteRough(let rough):
            // Submit once. Offering the polish as another paste duplicates
            // text that has already reached the destination.
            var finalText = rough
            if !recordingVocabulary.contextCorrectionEnabled, !recordingTranscription.backend.mergesCorrection,
               Policy.shouldCallPolish(transcript: rough, polishEnabled: config.polish.enabled),
               OutputPolicy.correctionWarning(outcome: timing.correctionOutcome) == nil {
                if !pathSatisfied {
                    timing.correctionOutcome = CloudRecovery.offline(transcript: rough).outcome
                } else {
                    do {
                        updateUI(for: job) { self.panel.showWorking(.correcting) }
                        timing.correctionProvider = (try? CloudAccess.preferences.load().provider.rawValue)
                        var transfer: TranscriptionTransferTimings?
                        let polished = try polish(rough, config: config, cancellation: cancellation, onTimings: { transfer = $0 })
                        timing.correctionTransfer = transfer
                        if SpeechContent.hasWords(polished) {
                            finalText = polished
                            timing.correctionOutcome = polished == rough ? "unchanged" : "corrected"
                        }
                    } catch {
                        let decision = CloudRecovery.correctionFallback(skipped: cancellation.didSkipCloud, cancelled: cancellation.isCancelled, failure: error as? CloudError, transcript: rough)
                        guard decision.pasteOnce else { return }
                        timing.correctionOutcome = decision.outcome
                        if decision.outcome != "skipped" { timing.saveCorrectionFailure() }
                        finalText = decision.text
                    }
                }
            }
            offerOnce(finalText, outcome: timing.correctionOutcome, job: job, timing: timing)
        case .waitForEnglish(let chinese):
            updateUI(for: job) { self.status.button?.title = "翻譯"; self.panel.showWorking(.translating) }
            if !pathSatisfied {
                updateUI(for: job) { self.panel.hide(); self.notices.showFailure(title: "翻譯未完成", detail: "目前離線，未送出翻譯。") }
                return
            }
            let translationStarted = DispatchTime.now().uptimeNanoseconds
            do {
                let english = try translate(chinese, config: config, vocabulary: recordingVocabulary, cancellation: cancellation)
                timing.translationSeconds = Double(DispatchTime.now().uptimeNanoseconds - translationStarted) / 1e9
                guard SpeechContent.hasWords(english) else {
                    updateUI(for: job) { self.panel.hide() }
                    return
                }
                offerOnce(english, outcome: timing.correctionOutcome, job: job, timing: timing)
            } catch {
                let decision = CloudRecovery.translationFallback(skipped: cancellation.didSkipCloud, cancelled: cancellation.isCancelled, chinese: chinese)
                if decision.pasteOnce {
                    timing.correctionOutcome = decision.outcome
                    offerOnce(decision.text, outcome: decision.outcome, job: job, timing: timing)
                    return
                }
                guard !cancellation.isCancelled else { return }
                let reason = (error as? CloudError)?.errorDescription ?? "翻譯失敗，請稍後再試。"
                updateUI(for: job) { self.panel.hide(); self.notices.showFailure(title: "翻譯未完成", detail: reason) }
            }
        }
    }

    private func offerOnce(_ text: String, outcome: String, job: ProcessingJob, timing: DictationTiming) {
        guard let delivered = try? OutputPolicy.forDelivery(text), !delivered.isEmpty else {
            updateUI(for: job) { self.panel.hide(); self.notices.showFailure(title: "文字未輸出", detail: "繁體中文轉換失敗，本次沒有輸出文字。") }
            return
        }
        var ready = timing
        ready.timeToPasteReadySeconds = ready.elapsed()
        updateUI(for: job) {
            if OutputPolicy.acceptsModelText(outcome: outcome) {
                self.correctionDegraded = false
                self.setStatus(AppIdentity.displayName)
            }
            if OutputPolicy.correctionNotice(outcome: outcome) != nil {
                self.retryContext = RetryContext(text: delivered, settings: job.vocabulary, config: job.config)
            }
            self.pendingTiming = ready
            self.panel.showPending(delivered, warning: OutputPolicy.correctionWarning(outcome: outcome), outcome: outcome)
            self.paster.offer(delivered, into: job.targetPID, acceptModelText: OutputPolicy.acceptsModelText(outcome: outcome))
        }
    }

    private func setStatus(_ title: String) {
        guard correctionDegraded else { status.button?.title = title; return }
        let text = NSMutableAttributedString(string: title + " ", attributes: [.foregroundColor: NSColor.labelColor])
        text.append(NSAttributedString(string: "●", attributes: [.foregroundColor: NSColor.systemOrange]))
        status.button?.attributedTitle = text
    }

    private func prewarmCorrectionConnection() {
        guard recordingVocabulary.contextCorrectionEnabled,
              let provider = try? CloudAccess.preferences.load().provider,
              let url = ConnectionWarmup.hostURL(from: provider.endpoint),
              let host = url.host else { return }
        let now = Date()
        guard ConnectionWarmup.shouldSend(offlineProbe: CloudAccess.offlineProbe, pathSatisfied: pathSatisfied, host: host, now: now, lastSent: warmedAt[host]) else { return }
        warmedAt[host] = now
        CloudClient.shared.prewarm(url)
    }

    /// Keyless TLS warmup for the cloud audio host, on the audio client's own session.
    private func prewarmAudioConnection() {
        guard recordingTranscription.backend.isCloud, recordingTranscription.cloudAudioConsent else { return }
        let endpoint = recordingTranscription.backend == .openAI ? URL(string: "https://api.openai.com/")! : GeminiAudioWire.transcribeEndpoint
        guard let url = ConnectionWarmup.hostURL(from: endpoint), let host = url.host else { return }
        let now = Date(); let key = "audio:" + host
        guard ConnectionWarmup.shouldSend(offlineProbe: CloudAccess.offlineProbe, pathSatisfied: pathSatisfied, host: host, now: now, lastSent: warmedAt[key]) else { return }
        warmedAt[key] = now
        CloudAudioClient.shared.prewarm(url)
    }

    private func copyRetryText() {
        guard let text = retryContext?.text else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    private func retryLastCorrection() {
        guard let context = retryContext else { return }
        notices.hide()
        retryContext = context
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let corrected = try ContextCorrectionService.correct(context.text, settings: context.settings, config: context.config)
                let delivered = try OutputPolicy.forDelivery(corrected)
                DispatchQueue.main.async {
                    guard let self else { return }
                    let board = NSPasteboard.general
                    board.clearContents()
                    board.setString(delivered, forType: .string)
                    self.retryContext = nil
                    self.correctionDegraded = false
                    self.setStatus(AppIdentity.displayName)
                    self.notices.showCopied()
                }
            } catch {
                let reason = (error as? CloudError)?.errorDescription ?? "校正請求失敗，請稍後再試。"
                DispatchQueue.main.async { self?.notices.showFailure(title: "重試未完成", detail: reason) }
            }
        }
    }

    private func polish(_ text: String, config: AppConfig, cancellation: ProcessingCancellation, onTimings: ((TranscriptionTransferTimings?) -> Void)? = nil) throws -> String {
        let body = ChatDraft.polish(text: text, timeout: .infinity)
        return try CloudAccess.complete(body, purpose: .correction, cancellation: cancellation, onTimings: onTimings)
    }

    private func translate(_ text: String, config: AppConfig, vocabulary: VocabularySettings, cancellation: ProcessingCancellation) throws -> String {
        let body: ChatBody
        if vocabulary.contextCorrectionEnabled {
            body = try ContextCorrection.translationDraft(text: text, entries: vocabulary.entries,
                timeout: config.translate.timeoutSeconds, reasoningEffort: config.translate.reasoningEffort)
        } else {
            body = ChatDraft.translate(text: text, timeout: config.translate.timeoutSeconds, reasoningEffort: config.translate.reasoningEffort)
        }
        return try CloudAccess.complete(body, purpose: .translation, cancellation: cancellation)
    }

    private func finishTiming() {
        guard var timing = pendingTiming else { return }
        pendingTiming = nil
        timing.timeToPasteConfirmedSeconds = paster.lastInsertionConfirmed ? timing.elapsed() : 0
        let info = ResidentSpeechEngine.shared.diagnostics
        timing.workerPID = info.pid
        timing.metal = info.metal
        timing.recordedAt = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(timing) {
            try? data.write(to: AppPaths.projectRoot().appendingPathComponent("Config/last-latency.json"), options: .atomic)
        }
    }

    private func cleanup(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
if let first = args.first, ["verify-key", "set-key", "delete-key", "transcribe", "self-check", "help"].contains(first) {
    if first == "self-check" {
        exit(SelfCheck.run())
    }
    exit(CLI.run(CommandLine.arguments))
}

if args.first == "speech-benchmark" { exit(SpeechBenchmark.run(arguments: args)) }
if args.first == "correction-probe" { exit(ContextCorrectionService.probe(onlyProtest: args.contains("--protest"), onlyPunctuation: args.contains("--punctuation"))) }
if args.first == "focus-probe", args.count >= 2 { exit(MuseFocusProbe.run(args[1], activate: args.dropFirst(2).contains("--activate"), summary: args.dropFirst(2).contains("--summary"))) }
let app = NSApplication.shared
if args.first == "clipboard-probe" { exit(ClipboardProbe.run()) }
if args.first == "recording-ready-probe" {
    app.setActivationPolicy(.accessory)
    for preset in SoundPreset.allCases {
        guard CaptureProbe.cueOnly(preset: preset, checkRecognition: false) == 0 else { exit(1) }
    }
    print("recording-ready-probe-passed=true")
    exit(0)
}
if args.first == "capture-fixture", args.count == 3 {
    exit(CaptureProbe.convert(input: URL(fileURLWithPath: args[1]), output: URL(fileURLWithPath: args[2])))
}
if args.first == "cue-cycle-probe", args.count == 1 {
    app.setActivationPolicy(.accessory)
    for preset in SoundPreset.allCases {
        guard CaptureProbe.cueOnly(preset: preset) == 0 else { exit(1) }
    }
    print("cue-cycle-probe-passed=true")
    exit(0)
}
if args.first == "cue-probe", args.count == 2, let preset = SoundPreset(rawValue: args[1]) {
    app.setActivationPolicy(.accessory)
    exit(CaptureProbe.cueOnly(preset: preset))
}
if args.first == "paste-timing-probe" { exit(PasteTimingProbe.run(arguments: args)) }
if args.first == "paste-probe" {
    exit(PasteProbe.run(arguments: args))
}
if ["silence-probe", "no-speech-probe"].contains(args.first ?? ""), args.count == 2 {
    app.setActivationPolicy(.accessory)
    exit(AppController().runSilenceProbe(source: URL(fileURLWithPath: args[1]), requireDigitalSilence: args.first == "silence-probe"))
}
if args.first == "dictionary-preview" {
    // Isolated visual QA: no personal dictionary, key table or microphone.
    let words = ["Hermes", "grok bot", "claude", "threads", "cybercab", "pe", "prompt", "edgelesstype"]
    let editor = VocabularyWindow(settings: VocabularySettings(contextCorrectionEnabled: true,
        entries: words.map { VocabularyEntry(word: $0) }))
    editor.setModelStatus("Large-v3 Turbo · Metal GPU · 已常駐")
    editor.onClose = { app.terminate(nil) }
    app.setActivationPolicy(.regular)
    editor.showWindow(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
    exit(0)
}
if args.first == "sound-settings-preview" {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("edgelesstype-sounds-ui-" + UUID().uuidString)
    let player = SoundPlayer(store: SoundSettingsStore(url: root.appendingPathComponent("sounds.json")))
    let editor = SoundSettingsWindow(player: player)
    editor.onClose = { try? FileManager.default.removeItem(at: root); app.terminate(nil) }
    app.setActivationPolicy(.regular)
    editor.showWindow(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
    exit(0)
}
if args.first == "api-settings-preview" {
    // Isolated UI QA: never read or modify the user's real key table.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("edgelesstype-ui-" + UUID().uuidString)
    let keys = SecretLocations(keyringDirectory: root.appendingPathComponent("keys"), keyringFile: root.appendingPathComponent("keys/ring.json"), storeFile: root.appendingPathComponent("private/credentials.encrypted.json"))
    let editor = APISettingsWindow(preferencesStore: CloudPreferencesStore(url: root.appendingPathComponent("cloud.json")), keyLocations: keys)
    editor.onClose = { try? FileManager.default.removeItem(at: root); app.terminate(nil) }
    app.setActivationPolicy(.regular)
    editor.showWindow(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
    exit(0)
}
let controller = AppController()
app.setActivationPolicy(.regular)
app.delegate = controller
app.run()
