import Foundation
import EdgelessTypeCore

/// Local timing and outcome only: no recording, transcript, clipboard value, or dictionary.
struct DictationTiming: Codable {
    var startedUptime: UInt64
    var mode: String
    var model: String
    var recordingStopSeconds: Double = 0
    var recognitionSeconds: Double = 0
    var correctionSeconds: Double = 0
    var translationSeconds: Double = 0
    var audioTransfer: TranscriptionTransferTimings?
    var correctionTransfer: TranscriptionTransferTimings?
    var correctionOutcome = "not_requested"
    var correctionProvider: String?
    var timeToPasteReadySeconds: Double = 0
    var timeToPasteConfirmedSeconds: Double = 0
    var manualPaste = false
    var workerPID: Int32?
    var metal = false
    var recordedAt = ""
    var audioSeconds: Double = 0
    /// Cloud requests sent for this recording; 0 when recognition was local from the start.
    var cloudAttempts = 0
    /// Why local Whisper supplied the text in cloud mode: slow (timer), chosen (Fn), failed, empty. Nil when the cloud text was pasted.
    var localReason: String?

    func saveCorrectionFailure() {
        guard !["not_requested", "corrected", "unchanged", "merged", "skipped"].contains(correctionOutcome) else { return }
        let status = ["outcome": correctionOutcome, "provider": correctionProvider ?? "unknown",
                      "recordedAt": ISO8601DateFormatter().string(from: Date())]
        let url = AppPaths.projectRoot().appendingPathComponent("Config/last-correction-failure.json")
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - startedUptime)/1e9 }
}

/// Why cloud recognition failed: error kind and reply metadata only, no recording or text. Keeps the latest 20 entries.
enum TranscriptionFailureLog {
    static func save(backend: TranscriptionBackend, error: Error, attempt: Int, evidence: [String: String]?) {
        var entry: [String: Any] = ["recordedAt": ISO8601DateFormatter().string(from: Date()), "backend": backend.rawValue,
                                    "attempt": attempt, "error": (error as? CloudError)?.rawValue ?? "\(type(of: error)).\(error)"]
        if let evidence { entry["evidence"] = evidence }
        let url = AppPaths.projectRoot().appendingPathComponent("Config/transcription-failures.json")
        let previous = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        guard let data = try? JSONSerialization.data(withJSONObject: Array((previous + [entry]).suffix(20)), options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// One line of numbers per pasted dictation, so slow waits can be counted instead of remembered. Keeps the latest 500.
enum LatencyHistory {
    static func append(_ timing: DictationTiming) {
        var entry: [String: Any] = ["recordedAt": timing.recordedAt, "mode": timing.mode, "model": timing.model,
                                    "audioSeconds": timing.audioSeconds, "recognitionSeconds": timing.recognitionSeconds,
                                    "correctionSeconds": timing.correctionSeconds, "translationSeconds": timing.translationSeconds,
                                    "timeToPasteReadySeconds": timing.timeToPasteReadySeconds, "cloudAttempts": timing.cloudAttempts,
                                    "correctionOutcome": timing.correctionOutcome, "manualPaste": timing.manualPaste]
        if let reason = timing.localReason { entry["localReason"] = reason }
        if let transfer = timing.audioTransfer, let data = try? JSONEncoder().encode(transfer),
           let numbers = try? JSONSerialization.jsonObject(with: data) { entry["audioTransfer"] = numbers }
        let url = AppPaths.projectRoot().appendingPathComponent("Config/latency-history.json")
        let previous = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        guard let data = try? JSONSerialization.data(withJSONObject: Array((previous + [entry]).suffix(500)), options: [.sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
