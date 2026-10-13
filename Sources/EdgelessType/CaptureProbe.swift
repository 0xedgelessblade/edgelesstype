import AppKit
import AVFoundation
import EdgelessTypeCore

/// Explicit local probes. No key access, cloud, clipboard or personal transcript
/// output. Real microphone capture happens only for the opt-in cue-probe command.
enum CaptureProbe {
    static func convert(input: URL, output: URL) -> Int32 {
        do {
            let source = try AVAudioFile(forReading: input)
            let sink = try CaptureFile(url: output, inputFormat: source.processingFormat)
            let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 512)!
            while source.framePosition < source.length {
                try source.read(into: buffer)
                try sink.append(buffer)
            }
            try sink.finish()
            print("capture-fixture-converted")
            return 0
        } catch { print("capture-fixture-failed"); return 1 }
    }

    static func cueOnly(preset: SoundPreset, checkRecognition: Bool = true) -> Int32 {
        CloudAccess.offlineProbe = true
        var done = false
        var result: Int32 = 1
        let recorder = Recorder()
        let config: AppConfig
        do { config = try AppPaths.loadConfig() }
        catch { print("cue-probe-config-failed"); return 2 }
        // Only this explicit test command opens the microphone for three seconds.
        // Tests run in a temporary app with public fixture configuration.
        var granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            var replied = false
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                DispatchQueue.main.async { granted = allowed; replied = true }
            }
            let deadline = Date().addingTimeInterval(45)
            while !replied && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        guard granted else { print("cue-probe-microphone-permission-required"); return 2 }
        let cueURL = Bundle.main.url(forResource: preset.resource(for: .start), withExtension: "wav")
        guard cueURL != nil else { print("cue-probe-missing-sound"); return 2 }
        let fail = {
            print("cue-probe-capture-failed")
            if let url = recorder.stop() { try? FileManager.default.removeItem(at: url) }
            done = true
        }
        let began = Date()
        do {
            _ = try recorder.start(cueURL: cueURL, onReady: {
                print("cue-probe-first-buffer-before-cue=true ready-ms=\(Int(Date().timeIntervalSince(began) * 1000))")
                DispatchQueue.main.asyncAfter(deadline: .now() + (checkRecognition ? 3 : 0.5)) {
                    guard let url = recorder.stop() else { done = true; return }
                    if !checkRecognition {
                        try? FileManager.default.removeItem(at: url)
                        result = 0; done = true
                        print("recording-ready-probe-capture-stopped=true")
                        return
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        defer { try? FileManager.default.removeItem(at: url) }
                        let transcript = try? Transcriber(config: config).transcribe(url: url)
                        // Match the app's meaningful-text gate. A punctuation-
                        // only ASR result is dropped before cloud or clipboard.
                        let empty = transcript.map { !SpeechContent.hasWords($0) } ?? false
                        DispatchQueue.main.async {
                            result = empty && CloudAccess.offlineProbeRequests == 0 ? 0 : 1
                            print("cue-probe-empty=\(empty) cloudRequests=\(CloudAccess.offlineProbeRequests)")
                            done = true
                        }
                    }
                }
                return true
            }, onFailure: fail)
        } catch {
            print("cue-probe-start-error-code=\((error as NSError).code) stage=\(recorder.failureStage)")
            fail()
        }
        // Recognition is bounded by its normal local worker timeout.
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        ResidentSpeechEngine.shared.shutdown()
        return result
    }
}
