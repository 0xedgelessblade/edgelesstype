import Foundation

/// Local timing and outcome only: no recording, transcript, clipboard value, or dictionary.
struct DictationTiming: Codable {
    var startedUptime: UInt64
    var mode: String
    var model: String
    var recordingStopSeconds: Double = 0
    var recognitionSeconds: Double = 0
    var correctionSeconds: Double = 0
    var correctionOutcome = "not_requested"
    var correctionProvider: String?
    var timeToPasteReadySeconds: Double = 0
    var timeToPasteConfirmedSeconds: Double = 0
    var manualPaste = false
    var workerPID: Int32?
    var metal = false
    var recordedAt = ""

    func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - startedUptime)/1e9 }
}
