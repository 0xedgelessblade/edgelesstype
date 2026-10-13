import Foundation

public enum TranscriptionBackend: String, Codable, CaseIterable {
    case localWhisper, openAI
    public var title: String { self == .localWhisper ? "Whisper（本機）" : "GPT Transcribe（OpenAI 雲端）" }
}

public enum TranscriptionError: LocalizedError, Equatable {
    case cloudNotEnabled, audioUnavailable, audioTooLarge, invalidAudio, missingOpenAIKey, busy
    public var errorDescription: String? {
        switch self {
        case .cloudNotEnabled: return "尚未同意使用 OpenAI 雲端語音辨識。請先勾選同意，再儲存雲端選擇。"
        case .audioUnavailable: return "無法讀取錄音，本次未傳送音訊。"
        case .audioTooLarge: return "錄音超過 OpenAI 的 25 MB 限制。請分段錄製，或切換本機 Whisper。"
        case .invalidAudio: return "錄音格式無效，本次未傳送音訊。"
        case .missingOpenAIKey: return "尚未設定可用的 OpenAI 金鑰。請到「語音辨識」開啟 OpenAI 金鑰設定。"
        case .busy: return "請等這次錄音與文字處理完成，再切換語音辨識方式。"
        }
    }
}

public struct TranscriptionPreferences: Codable, Equatable {
    public var backend: TranscriptionBackend
    public var cloudAudioConsent: Bool
    public init(backend: TranscriptionBackend = .localWhisper, cloudAudioConsent: Bool = false) {
        self.backend = backend; self.cloudAudioConsent = cloudAudioConsent
    }
    public func validated() throws -> Self {
        guard backend != .openAI || cloudAudioConsent else { throw TranscriptionError.cloudNotEnabled }
        return self
    }
}

public struct TranscriptionPreferencesStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> TranscriptionPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        return try JSONDecoder().decode(TranscriptionPreferences.self, from: Data(contentsOf: url)).validated()
    }
    public func save(_ preferences: TranscriptionPreferences) throws {
        let value = try preferences.validated()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

public enum TranscriptionRouter {
    public static func run(_ preferences: TranscriptionPreferences, local: () throws -> String, cloud: () throws -> String) throws -> String {
        let selection = try preferences.validated()
        switch selection.backend {
        case .localWhisper: return try local()
        case .openAI: return try cloud()
        }
    }
}

public enum OpenAITranscriptionWire {
    public static let model = "gpt-transcribe"
    public static let maximumAudioBytes = 25_000_000
    public static func request(audio: Data, preferences: TranscriptionPreferences, key: String) throws -> URLRequest {
        guard try preferences.validated().backend == .openAI else { throw TranscriptionError.cloudNotEnabled }
        guard !key.isEmpty else { throw CloudError.missingKey }
        guard !key.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else { throw CloudError.invalidKey }
        guard audio.count <= maximumAudioBytes else { throw TranscriptionError.audioTooLarge }
        guard audio.count > 44, audio.prefix(4) == Data("RIFF".utf8), audio.subdata(in: 8..<12) == Data("WAVE".utf8) else { throw TranscriptionError.invalidAudio }
        let boundary = "edgelesstype-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model)
        field("prompt", "這是一段口述轉寫。中文使用繁體，保留原本的英文與標點。")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"; request.timeoutInterval = 180
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
    public static func parse(_ data: Data, status: Int) throws -> String {
        guard (200...299).contains(status) else {
            switch status {
            case 400, 404: throw CloudError.invalidRequest
            case 401, 403: throw CloudError.authentication
            case 402, 429: throw CloudError.quota
            case 408: throw CloudError.timeout
            case 413: throw TranscriptionError.audioTooLarge
            default: throw CloudError.unavailable
            }
        }
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["error"] == nil, let text = value["text"] as? String else { throw CloudError.invalidResponse }
        // Empty speech is a valid no-output result; do not invent text.
        return try OutputPolicy.traditional(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Explicit opt-in audio upload; no logging, persistent cache or redirects.
public final class OpenAITranscriptionClient: NSObject, URLSessionTaskDelegate {
    public static let shared = OpenAITranscriptionClient()
    private let session: URLSession
    private let transport: PrivateHTTPDelegate
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForResource = 600
        let delegate = PrivateHTTPDelegate()
        transport = delegate
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        super.init()
    }
    deinit { session.invalidateAndCancel() }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    public func transcribe(audio: Data, preferences: TranscriptionPreferences, key: String,
                           onProgress: ((Double) -> Void)? = nil,
                           onTimings: ((TranscriptionTransferTimings) -> Void)? = nil, cancellation: ProcessingCancellation? = nil) throws -> String {
        try cancellation?.check()
        var request = try OpenAITranscriptionWire.request(audio: audio, preferences: preferences, key: key)
        let body = request.httpBody!
        request.httpBody = nil
        let gate = DispatchSemaphore(value: 0)
        let box = TranscriptionResultBox()
        let task = session.uploadTask(with: request, from: body) { data, response, error in
            if let error { box.value = .failure((error as? URLError)?.code == .timedOut ? CloudError.timeout : CloudError.network) }
            else if let data, let response = response as? HTTPURLResponse {
                box.value = Result { try OpenAITranscriptionWire.parse(data, status: response.statusCode) }
            } else { box.value = .failure(CloudError.invalidResponse) }
            gate.signal()
        }
        transport.track(task, progress: onProgress)
        defer { if let value = transport.finish(task) { onTimings?(value) } }
        onProgress?(0)
        let registration = cancellation?.register { task.cancel(); gate.signal() }
        defer { cancellation?.unregister(registration) }
        try cancellation?.check()
        task.resume()
        guard gate.wait(timeout: .now() + 601) == .success else { task.cancel(); throw CloudError.timeout }
        try cancellation?.check()
        return try box.value.get()
    }
}

private final class TranscriptionResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<String, Error> = .failure(CloudError.network)
    var value: Result<String, Error> { get { lock.lock(); defer { lock.unlock() }; return result } set { lock.lock(); defer { lock.unlock() }; result = newValue } }
}
