import Foundation
import EdgelessTypeCore

enum SpeechBenchmark {
    struct Sample: Codable { var id: String; var path: String; var reference: String; var source: String; var duration: Double }
    struct Trial: Codable {
        var profile: String; var round: Int; var sample: Sample
        var raw: String; var final: String
        var recognitionSeconds: Double; var correctionSeconds: Double; var readyToPasteSeconds: Double
        var correctionFailed: Bool; var workerPID: Int32?; var modelLaunches: Int; var metal: Bool; var device: String
    }
    struct Boot: Codable { var profile: String; var seconds: Double; var pid: Int32?; var metal: Bool; var device: String }
    struct Report: Codable { var engineVersion: String; var timingScope: String; var boots: [Boot]; var trials: [Trial] }

    static func run(arguments: [String]) -> Int32 {
        guard arguments.count >= 4 else { print("speech-benchmark <corpus.json> <gpu-config.json> <report.json> [profile]"); return 2 }
        defer { ResidentSpeechEngine.shared.shutdown() }
        do {
            let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
            let gpu = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
            let settings = try AppPaths.vocabularyStore.load(fallbackTerms: gpu.terms)
            var report = Report(engineVersion: "whisper.cpp v1.8.1 a91dd3be72f70dd1b3cb6e252f35fa17b93f596c",
                timingScope: "Monotonic wall clock from an already finalized WAV until local speech recognition and cloud context correction finish. Excludes the user's speaking time, microphone file finalization, and the subsequent paste key delivery. Raw recognition and correction timings are separate. No polishing.", boots: [], trials: [])
            let output = URL(fileURLWithPath: arguments[3])
            func save() throws {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try encoder.encode(report).write(to: output, options: .atomic)
            }
            let profiles = arguments.count > 4 ? [arguments[4]] : ["small-cpu-cold", "small-metal-resident", "turbo-metal-resident"]
            for profile in profiles {
                var config = gpu
                if profile == "small-cpu-cold" {
                    config.modelPath = gpu.residentSpeech!.smallModelPath
                    config.residentSpeech = nil
                } else {
                    config.residentSpeech?.selectedModel = profile == "small-metal-resident" ? "small" : "turbo"
                }
                let bootStart = DispatchTime.now().uptimeNanoseconds
                if config.residentSpeech != nil { try ResidentSpeechEngine.shared.warmUp(config: config) }
                let bootInfo = ResidentSpeechEngine.shared.diagnostics
                let bootSeconds = Double(DispatchTime.now().uptimeNanoseconds - bootStart) / 1e9
                report.boots.append(Boot(profile: profile, seconds: bootSeconds, pid: bootInfo.pid, metal: bootInfo.metal, device: bootInfo.device))
                print("BOOT \(profile) \(String(format: "%.3f", bootSeconds))s metal=\(bootInfo.metal) pid=\(bootInfo.pid ?? 0)")
                fflush(stdout)
                for round in 1...2 {
                    for sample in samples {
                        let begin = DispatchTime.now().uptimeNanoseconds
                        let raw = try Transcriber(config: config, vocabulary: settings).transcribe(url: URL(fileURLWithPath: sample.path))
                        let recognized = DispatchTime.now().uptimeNanoseconds
                        var failed = false
                        let corrected: String
                        do { corrected = try ContextCorrectionService.correct(raw, settings: settings, config: config) }
                        catch { corrected = raw; failed = true }
                        let completed = DispatchTime.now().uptimeNanoseconds
                        let info = ResidentSpeechEngine.shared.diagnostics
                        report.trials.append(Trial(profile: profile, round: round, sample: sample, raw: raw, final: corrected,
                            recognitionSeconds: Double(recognized - begin)/1e9, correctionSeconds: Double(completed - recognized)/1e9,
                            readyToPasteSeconds: Double(completed - begin)/1e9, correctionFailed: failed,
                            workerPID: info.pid, modelLaunches: info.launches, metal: info.metal, device: info.device))
                        try save()
                        print("TRIAL \(profile) r\(round) \(sample.id) speech=\(String(format:"%.3f", Double(recognized-begin)/1e9))s ready=\(String(format:"%.3f",Double(completed-begin)/1e9))s correctionFailed=\(failed)")
                        fflush(stdout)
                    }
                }
                ResidentSpeechEngine.shared.shutdown()
            }
            try save()
            return 0
        } catch { print("Benchmark failed: \(error.localizedDescription)"); return 1 }
    }
}
