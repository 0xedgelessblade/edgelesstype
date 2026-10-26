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
