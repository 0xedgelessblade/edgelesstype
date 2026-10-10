import AppKit
import AVFoundation
import OpenTypelessCore

/// Start capture immediately; announce readiness only after audio reaches disk.
/// The cue may enter the microphone. No echo-cancellation startup or audio trim.
final class Recorder {
    private(set) var failureStage = "setup"
    private let engine = AVAudioEngine()
    private var cue: NSSound?
    private let lock = NSLock()
    private var sink: CaptureFile?
    private var active = false
    private var announced = false
    private var failed = false
    private var tapped = false
    private var observer: NSObjectProtocol?
    private var url: URL?

    func start(cueURL: URL?, onReady: @escaping () -> Bool, onFailure: @escaping () -> Void) throws -> URL {
        precondition(Thread.isMainThread)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("edgelesstype-\(UUID().uuidString).wav")
        self.url = url
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }
        failureStage = "file"
        sink = try CaptureFile(url: url, inputFormat: format)
        cue = cueURL.flatMap { NSSound(contentsOf: $0, byReference: true) }
        active = true
        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            guard self.active, !self.failed else { self.lock.unlock(); return }
            do {
                try self.sink?.append(buffer)
                let ready = (self.sink?.framesWritten ?? 0) > 0 && !self.announced
                if ready { self.announced = true }
                self.lock.unlock()
                if ready {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isActive else { return }
                        guard onReady() else {
                            if let url = self.stop() { try? FileManager.default.removeItem(at: url) }; return
                        }
                        // The first audio buffer is already on disk. Never use
                        // a fixed delay, process launch, or cue duration as ready.
                        self.cue?.play()
                    }
                }
            } catch {
                self.failed = true
                self.lock.unlock()
                DispatchQueue.main.async { [weak self] in
                    guard self?.isActive == true else { return }
                    onFailure()
                }
            }
        }
        tapped = true
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // A running engine is still valid; genuine route changes stop it.
            guard let self, self.isActive, !self.engine.isRunning else { return }
            onFailure()
        }
        failureStage = "start"
        do { engine.prepare(); try engine.start() }
        catch {
            if let url = stop() { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.isActive else { return }
            self.lock.lock(); let pending = !self.announced; self.lock.unlock()
            if pending { onFailure() }
        }
        return url
    }

    private var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }

    func stop() -> URL? {
        precondition(Thread.isMainThread)
        lock.lock(); active = false; lock.unlock()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        cue?.stop()
        cue = nil
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        lock.lock()
        do { try sink?.finish() } catch { failed = true }
        sink = nil // Close the WAV and commit its header before transcription.
        let result = failed ? nil : url
        if failed, let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        lock.unlock()
        return result
    }
}

enum CaptureError: Error { case noInput, conversion }

/// Streaming conversion keeps every buffer, including samples before the cue.
/// Also exercised with local speech fixtures without opening the microphone.
final class CaptureFile {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private(set) var framesWritten: AVAudioFramePosition = 0
    init(url: URL, inputFormat: AVAudioFormat) throws {
        outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { throw CaptureError.conversion }
        self.converter = converter
        file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
    }
    func append(_ buffer: AVAudioPCMBuffer) throws {
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { throw CaptureError.conversion }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return buffer
        }
        if error != nil || status == .error { throw CaptureError.conversion }
        if output.frameLength > 0 { try file.write(from: output); framesWritten += AVAudioFramePosition(output.frameLength) }
    }
}

extension CaptureFile {
    func finish() throws {
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1024) else { throw CaptureError.conversion }
        while true {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                state.pointee = .endOfStream; return nil
            }
            if error != nil || status == .error { throw CaptureError.conversion }
            if output.frameLength > 0 { try file.write(from: output); framesWritten += AVAudioFramePosition(output.frameLength) }
            if status == .endOfStream || output.frameLength == 0 { break }
        }
    }
}
