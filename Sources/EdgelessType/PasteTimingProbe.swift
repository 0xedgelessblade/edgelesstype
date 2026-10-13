import AppKit
import Foundation
import EdgelessTypeCore

/// Controlled replay of fixed test WAVs through the production transcriber,
/// correction service, preview panel, hotkey monitor, and Paster.
enum PasteTimingProbe {
    struct Row: Codable {
        var profile: String; var sampleID: String; var audioSeconds: Double
        var recognitionSeconds: Double; var readySeconds: Double; var visibleSeconds: Double
        var confirmed: Bool; var correctionFailed: Bool
        var workerPID: Int32?; var metal: Bool
    }
    static func run(arguments: [String]) -> Int32 {
        guard arguments.count == 5,
              let target = NSRunningApplication.runningApplications(withBundleIdentifier: arguments[3]).first else {
            print("paste-timing-probe <corpus.json> <gpu-config.json> <target bundle ID> <output.json>"); return 2
        }
        NSApp.setActivationPolicy(.accessory)
        let paster = Paster()
        let panel = RecordChrome()
        let monitor = HotkeyMonitor()
        monitor.onPasteKey = { control, own in paster.notePasteKey(controlOnly: control, fromUs: own) }
        guard monitor.install(), AXIsProcessTrusted() else { print("paste test permissions unavailable"); return 2 }
        defer { ResidentSpeechEngine.shared.shutdown(); panel.hide(); withExtendedLifetime(monitor) {} }
        do {
            let all = try JSONDecoder().decode([SpeechBenchmark.Sample].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
            let samples = all.filter { ["tts-01", "tts-03", "tts-09", "tts-10"].contains($0.id) }
            let base = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
            let settings = try AppPaths.vocabularyStore.load(fallbackTerms: base.terms)
            var rows: [Row] = []
            for profile in ["small-cpu-cold", "small-metal-resident", "turbo-metal-resident"] {
                var config = base
                if profile == "small-cpu-cold" {
                    config.modelPath = base.residentSpeech!.smallModelPath; config.residentSpeech = nil
                } else {
                    config.residentSpeech?.selectedModel = profile == "small-metal-resident" ? "small" : "turbo"
                    try ResidentSpeechEngine.shared.warmUp(config: config)
                }
                for sample in samples {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                        target.activate(options: [.activateIgnoringOtherApps])
                        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                    }
                    guard Paster.focusedElement(in: target.processIdentifier) != nil else {
                        throw SpeechEngineError.invalidResponse
                    }
                    var confirmed = false
                    var confirmedAt: UInt64 = 0
                    paster.onDismiss = { confirmed = true; confirmedAt = DispatchTime.now().uptimeNanoseconds; panel.hide() }
                    panel.showWorking()
                    let begin = DispatchTime.now().uptimeNanoseconds
                    let preparation = PreparedSpeechBox()
                    let sampleConfig = config
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let raw = try Transcriber(config: sampleConfig, vocabulary: settings).transcribe(url: URL(fileURLWithPath: sample.path))
                            let recognized = DispatchTime.now().uptimeNanoseconds
                            var failed = false
                            let text: String
                            do { text = try ContextCorrectionService.correct(raw, settings: settings, config: sampleConfig) }
                            catch { text = raw; failed = true }
                            preparation.set(.success(PreparedSpeech(text: text, recognized: recognized,
                                ready: DispatchTime.now().uptimeNanoseconds, failed: failed)))
                        } catch { preparation.set(.failure(error)) }
                    }
                    while preparation.get() == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                    let prepared = try preparation.get()!.get()
                    let text = prepared.text, recognized = prepared.recognized, ready = prepared.ready
                    let correctionFailed = prepared.failed
                    panel.showPending(text)
                    paster.offer(text, into: target.processIdentifier)
                    let deadline = Date().addingTimeInterval(4)
                    while !confirmed && Date() < deadline {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                    }
                    let end = confirmed ? confirmedAt : DispatchTime.now().uptimeNanoseconds
                    let info = ResidentSpeechEngine.shared.diagnostics
                    rows.append(Row(profile: profile, sampleID: sample.id, audioSeconds: sample.duration,
                        recognitionSeconds: Double(recognized-begin)/1e9, readySeconds: Double(ready-begin)/1e9,
                        visibleSeconds: Double(end-begin)/1e9, confirmed: confirmed, correctionFailed: correctionFailed,
                        workerPID: info.pid, metal: info.metal))
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(rows).write(to: URL(fileURLWithPath: arguments[4]), options: .atomic)
                    print("PASTE \(profile) \(sample.id) ready=\(String(format:"%.3f",Double(ready-begin)/1e9))s visible=\(String(format:"%.3f",Double(end-begin)/1e9))s confirmed=\(confirmed)")
                    fflush(stdout)
                    guard confirmed else { return 1 }
                }
                ResidentSpeechEngine.shared.shutdown()
            }
            return rows.count == 12 && rows.allSatisfy(\.confirmed) ? 0 : 1
        } catch { print("Paste replay failed: \(error.localizedDescription)"); return 1 }
    }
}

private struct PreparedSpeech {
    var text: String; var recognized: UInt64; var ready: UInt64; var failed: Bool
}
private final class PreparedSpeechBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<PreparedSpeech, Error>?
    func set(_ value: Result<PreparedSpeech, Error>) { lock.lock(); self.value = value; lock.unlock() }
    func get() -> Result<PreparedSpeech, Error>? { lock.lock(); defer { lock.unlock() }; return value }
}
