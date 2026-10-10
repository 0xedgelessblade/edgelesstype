import Foundation
import Darwin

struct ResidentSpeechConfig: Codable {
    var serverPath: String
    var smallModelPath: String
    var turboModelPath: String
    var selectedModel: String

    var modelPath: String { AppPaths.resolve(selectedModel == "small" ? smallModelPath : turboModelPath) }
    var displayName: String { selectedModel == "small" ? "Small" : "Large-v3 Turbo" }
}

enum SpeechEngineError: LocalizedError {
    case unavailable, missingGPU, invalidResponse, stopped
    var errorDescription: String? {
        switch self {
        case .unavailable: return "本機辨識服務未能啟動。"
        case .missingGPU: return "未確認 Metal GPU 已啟用。"
        case .invalidResponse: return "本機辨識服務沒有回傳有效文字。"
        case .stopped: return "本機辨識服務已停止。"
        }
    }
}

/// One model context and one child process for the app's entire lifetime.
/// Audio is posted only to an authenticated service on 127.0.0.1.
final class ResidentSpeechEngine {
    static let shared = ResidentSpeechEngine()
    private let operationLock = NSLock()
    private let stateLock = NSLock()
    private var worker: Process?
    private var modelKey = ""
    private var port = 0
    private var sessionToken = ""
    private var stderrPipe: Pipe?
    private var metalSeen = false
    private var ready = false
    private var gpuName = ""
    private var logTail = ""
    private var stopping = false
    private(set) var startCount = 0
    private var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 95
        return URLSession(configuration: configuration)
    }()

    var diagnostics: (pid: Int32?, launches: Int, metal: Bool, device: String, ready: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        return (worker?.isRunning == true ? worker?.processIdentifier : nil, startCount, metalSeen, gpuName, ready)
    }

    func warmUp(config: AppConfig) throws {
        operationLock.lock(); defer { operationLock.unlock() }
        try ensureReady(config: config)
    }

    func transcribe(url: URL, config: AppConfig, prompt: String) throws -> String {
        operationLock.lock(); defer { operationLock.unlock() }
        try ensureReady(config: config)
        stateLock.lock()
        let currentPort = port, token = sessionToken
        let pid = worker?.processIdentifier
        stateLock.unlock()
        let boundary = "OpenTypeless-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("language", config.language)
        field("prompt", prompt)
        field("no_context", "true")
        field("no_timestamps", "true")
        field("response_format", "json")
        field("temperature", "0.0")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"utterance.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: url))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(currentPort)/inference")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-OpenTypeless-Session")
        let data = try send(request, timeout: 95)
        stateLock.lock()
        let stillOurWorker = worker?.processIdentifier == pid && worker?.isRunning == true
        stateLock.unlock()
        guard stillOurWorker else { throw SpeechEngineError.stopped }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else { throw SpeechEngineError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shutdown() {
        stateLock.lock()
        stopping = true
        ready = false
        let process = worker
        worker = nil
        modelKey = ""
        let pipe = stderrPipe
        stderrPipe = nil
        stateLock.unlock()
        pipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
    }

    private func ensureReady(config: AppConfig) throws {
        guard let resident = config.residentSpeech else { throw SpeechEngineError.unavailable }
        let key = resident.serverPath + "|" + resident.modelPath + "|" + String(config.threads)
        stateLock.lock()
        let reusable = worker?.isRunning == true && modelKey == key && metalSeen && ready
        stateLock.unlock()
        if reusable { return }
        shutdown()
        guard FileManager.default.isExecutableFile(atPath: AppPaths.resolve(resident.serverPath)),
              FileManager.default.fileExists(atPath: resident.modelPath) else { throw SpeechEngineError.unavailable }
        let newPort = try availablePort()
        let token = UUID().uuidString + UUID().uuidString
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AppPaths.resolve(resident.serverPath))
        process.arguments = ["-m", resident.modelPath, "-t", String(config.threads), "-l", config.language,
                             "-nt", "-nc", "--host", "127.0.0.1", "--port", String(newPort)]
        var environment = ProcessInfo.processInfo.environment
        environment["OPEN_TYPELESS_SESSION_TOKEN"] = token
        environment["OPEN_TYPELESS_PARENT_PID"] = String(getpid())
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe
        stateLock.lock()
        worker = process; modelKey = key; port = newPort; sessionToken = token
        metalSeen = false; gpuName = ""; logTail = ""; stopping = false; stderrPipe = pipe
        stateLock.unlock()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.readDeviceMetadata(data)
        }
        do { try process.run() } catch { shutdown(); throw error }
        stateLock.lock(); startCount += 1; stateLock.unlock()
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            stateLock.lock(); let cancelled = stopping; stateLock.unlock()
            guard !cancelled, process.isRunning else { shutdown(); throw SpeechEngineError.unavailable }
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(newPort)/health")!)
            request.setValue(token, forHTTPHeaderField: "X-OpenTypeless-Session")
            request.timeoutInterval = 0.4
            if let data = try? send(request, timeout: 0.5),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               object["status"] == "ok" {
                stateLock.lock(); let gpu = metalSeen; stateLock.unlock()
                guard gpu else { Thread.sleep(forTimeInterval: 0.05); continue }
                stateLock.lock(); ready = true; stateLock.unlock()
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        shutdown()
        throw SpeechEngineError.unavailable
    }

    private func readDeviceMetadata(_ data: Data) {
        stateLock.lock(); defer { stateLock.unlock() }
        logTail += String(decoding: data, as: UTF8.self)
        let lines = logTail.components(separatedBy: "\n")
        logTail = String((lines.last ?? "").suffix(2048))
        for line in lines.dropLast() {
            if line.contains("whisper_backend_init_gpu: using Metal backend") { metalSeen = true }
            if let range = line.range(of: "GPU name:") {
                gpuName = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        // All other stderr, including any transcript text, is discarded.
    }

    private func availablePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SpeechEngineError.unavailable }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { throw SpeechEngineError.unavailable }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let status = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard status == 0 else { throw SpeechEngineError.unavailable }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private func send(_ request: URLRequest, timeout: TimeInterval) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        let result = SpeechHTTPResult()
        let task = session.dataTask(with: request) { data, response, error in
            if let error { result.set(.failure(error)) }
            else if (response as? HTTPURLResponse)?.statusCode != 200 { result.set(.failure(SpeechEngineError.invalidResponse)) }
            else { result.set(.success(data ?? Data())) }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut { task.cancel(); throw URLError(.timedOut) }
        return try result.get().get()
    }
}

private final class SpeechHTTPResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<Data, Error> = .failure(SpeechEngineError.invalidResponse)
    func set(_ value: Result<Data, Error>) { lock.lock(); self.value = value; lock.unlock() }
    func get() -> Result<Data, Error> { lock.lock(); defer { lock.unlock() }; return value }
}
