import Foundation

/// Gemini Live transcription: audio leaves in small pieces while the user is still speaking, so the text is nearly ready at release.
public enum GeminiLiveWire {
    public static let model = "gemini-3.5-transcribe-live"
    public static let endpoint = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
    /// 100 ms of 16 kHz mono 16-bit PCM.
    public static let chunkBytes = 3200
    /// After release the final text normally lands within a second; past this the local draft is used.
    public static let finalTimeout: TimeInterval = 4

    /// The key travels in a header, never in the URL.
    public static func request(key: String) throws -> URLRequest {
        guard !key.isEmpty else { throw CloudError.missingKey }
        guard !key.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else { throw CloudError.invalidKey }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        return request
    }

    /// Automatic language detection; the user's key press, not the server, decides where the utterance starts and ends.
    public static func setup(terms: [String]) -> [String: Any] {
        var transcription: [String: Any] = ["languageCodes": [String]()]
        let words = GeminiAudioWire.vocabulary(terms)
        if !words.isEmpty { transcription["customVocabulary"] = words }
        return ["setup": ["model": "models/" + model,
                          "generationConfig": ["responseModalities": ["TEXT"]],
                          "inputAudioTranscription": transcription,
                          "realtimeInputConfig": ["automaticActivityDetection": ["disabled": true]]]]
    }
    public static let activityStart: [String: Any] = ["realtimeInput": ["activityStart": [String: Any]()]]
    public static let activityEnd: [String: Any] = ["realtimeInput": ["activityEnd": [String: Any]()]]
    public static func audio(_ pcm: Data) -> [String: Any] {
        ["realtimeInput": ["audio": ["data": pcm.base64EncodedString(), "mimeType": "audio/pcm;rate=16000"]]]
    }

    public enum Event: Equatable { case ready, final(String), finished }

    /// Interim text is ignored: only finalized text is ever pasted.
    public static func events(_ message: Data) -> [Event] {
        guard let root = try? JSONSerialization.jsonObject(with: message) as? [String: Any] else { return [] }
        var events: [Event] = []
        if root["setupComplete"] != nil { events.append(.ready) }
        let content = root["serverContent"] as? [String: Any]
        if let text = (content?["inputTranscription"] as? [String: Any])?["text"] as? String, !text.isEmpty { events.append(.final(text)) }
        // Speech ends with generationComplete; a recording without speech only reports the activity end.
        if content?["generationComplete"] as? Bool == true || (root["voiceActivity"] as? [String: Any])?["type"] as? String == "ACTIVITY_END" {
            events.append(.finished)
        }
        return events
    }
}

/// The transport under a live session; replaced by a scripted one in tests.
public protocol LiveSocket: AnyObject {
    func send(_ text: String)
    func receive(_ completion: @escaping (Result<Data, Error>) -> Void)
    func close()
    /// HTTP status of a refused handshake, when there was one.
    var refusedStatus: Int? { get }
}

/// One recording, one connection. Audio that arrives before the server is ready waits in memory and is sent in order.
public final class LiveTranscriptionSession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "edgelesstype.live-transcription")
    private let socket: LiveSocket
    private let lock = NSLock()
    private var outcome: Result<String, Error>?
    private var ready = false
    private var ended = false
    private var endSent = false
    private var pending = Data()
    private var finals = ""
    private let opened = DispatchTime.now().uptimeNanoseconds
    private var readyAt: UInt64?
    private var endedAt: UInt64?
    private var finishedAt: UInt64?

    public init(socket: LiveSocket, terms: [String]) {
        self.socket = socket
        queue.async {
            self.send(GeminiLiveWire.setup(terms: terms))
            self.listen()
        }
    }

    public static func open(key: String, terms: [String]) throws -> LiveTranscriptionSession {
        LiveTranscriptionSession(socket: URLSessionLiveSocket(request: try GeminiLiveWire.request(key: key)), terms: terms)
    }

    /// 16 kHz mono 16-bit little-endian PCM, in capture order. Safe to call from the audio thread.
    public func append(_ pcm: Data) {
        queue.async {
            guard !self.ended, self.result == nil else { return }
            self.pending.append(pcm)
            if self.ready { self.flush(all: false) }
        }
    }

    /// The key was released: send what is left and ask for the final text.
    public func finish() {
        queue.async {
            guard !self.ended else { return }
            self.ended = true
            self.endedAt = DispatchTime.now().uptimeNanoseconds
            if self.ready { self.sendEnd() }
        }
    }

    public func cancel() {
        queue.async {
            self.settle(.failure(ProcessingError.cancelled))
        }
    }

    /// Waits for the final text after `finish()`. Skipping the cloud or cancelling the job stops the wait at once.
    public func waitForText(timeout: TimeInterval = GeminiLiveWire.finalTimeout, cancellation: ProcessingCancellation? = nil) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let result { return try result.get() }
            try cancellation?.check()
            if cancellation?.didSkipCloud == true { cancel(); throw ProcessingError.skippedCloud }
            if Date() >= deadline { cancel(); throw CloudError.timeout }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// Seconds from opening the connection to the server accepting audio; nil when it never did.
    public var connectSeconds: Double? { lock.lock(); defer { lock.unlock() }; return readyAt.map { Double($0 - opened) / 1e9 } }
    /// Seconds from release to the final text; nil when no text arrived.
    public var finalSeconds: Double? {
        lock.lock(); defer { lock.unlock() }
        guard let endedAt, let finishedAt, finishedAt >= endedAt else { return nil }
        return Double(finishedAt - endedAt) / 1e9
    }

    /// Lets tests wait until queued work has run.
    func drain() { queue.sync {} }

    private var result: Result<String, Error>? { lock.lock(); defer { lock.unlock() }; return outcome }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        socket.send(String(decoding: data, as: UTF8.self))
    }

    private func flush(all: Bool) {
        while pending.count >= GeminiLiveWire.chunkBytes || (all && !pending.isEmpty) {
            let piece = pending.prefix(GeminiLiveWire.chunkBytes)
            send(GeminiLiveWire.audio(Data(piece)))
            pending.removeFirst(piece.count)
        }
    }

    private func sendEnd() {
        guard !endSent else { return }
        flush(all: true)
        send(GeminiLiveWire.activityEnd)
        endSent = true
    }

    private func listen() {
        socket.receive { [weak self] message in
            guard let self else { return }
            self.queue.async {
                guard self.result == nil else { return }
                switch message {
                case .failure:
                    self.settle(.failure(self.socket.refusedStatus.map(AudioUploadPolicy.statusError) ?? CloudError.network))
                case .success(let data):
                    for event in GeminiLiveWire.events(data) { self.handle(event) }
                    if self.result == nil { self.listen() }
                }
            }
        }
    }

    private func handle(_ event: GeminiLiveWire.Event) {
        switch event {
        case .ready:
            guard !ready else { return }
            ready = true
            lock.lock(); readyAt = DispatchTime.now().uptimeNanoseconds; lock.unlock()
            send(GeminiLiveWire.activityStart)
            if ended { sendEnd() } else { flush(all: false) }
        case .final(let text):
            finals += text
        case .finished:
            // A pause can finish a segment while the key is still held; only the end we asked for completes the recording.
            if endSent { settle(.success(finals)) }
        }
    }

    private func settle(_ value: Result<String, Error>) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = value
        if case .success = value { finishedAt = DispatchTime.now().uptimeNanoseconds }
        lock.unlock()
        pending.removeAll()
        socket.close()
    }
}

/// No cache, cookies, stored credentials or redirects; the connection lives for one recording.
final class URLSessionLiveSocket: NSObject, LiveSocket, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var task: URLSessionWebSocketTask!

    init(request: URLRequest) {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: request)
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func send(_ text: String) { task.send(.string(text)) { _ in } }

    func receive(_ completion: @escaping (Result<Data, Error>) -> Void) {
        task.receive { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(.string(let text)): completion(.success(Data(text.utf8)))
            case .success(.data(let data)): completion(.success(data))
            case .success: completion(.success(Data()))
            }
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }

    var refusedStatus: Int? {
        guard let status = (task.response as? HTTPURLResponse)?.statusCode, !(200...299).contains(status), status != 101 else { return nil }
        return status
    }
}
