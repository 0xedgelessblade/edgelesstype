import Foundation

public enum CloudPurpose { case correction, translation }

/// A small, curated provider list. Keys can only be sent to these fixed hosts.
public enum CloudProvider: String, Codable, CaseIterable {
    case xai, google, anthropic, openai
    public var title: String {
        switch self { case .xai: return "xAI"; case .google: return "Google"; case .anthropic: return "Claude"; case .openai: return "OpenAI" }
    }
    public func model(for purpose: CloudPurpose) -> String {
        switch self {
        case .xai: return purpose == .translation ? "grok-4.7" : "grok-4.3"
        case .google: return "gemini-3.8-flash"
        case .anthropic: return "claude-haiku-5-5"
        case .openai: return "gpt-6-luna"
        }
    }
    public var correctionTimeoutSeconds: TimeInterval { .infinity }
    public var modelsDescription: String {
        "校正：\(model(for: .correction)) · 翻譯：\(model(for: .translation))"
    }
    public var keyPage: URL {
        switch self {
        case .xai: return URL(string: "https://console.x.ai/")!
        case .google: return URL(string: "https://aistudio.google.com/api-keys")!
        case .anthropic: return URL(string: "https://platform.claude.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        }
    }
    public var endpoint: URL {
        switch self {
        case .xai: return URL(string: "https://api.x.ai/v1/chat/completions")!
        case .google: return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model(for: .correction)):generateContent")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai: return URL(string: "https://api.openai.com/v1/responses")!
        }
    }
}

public struct CloudPreferences: Codable, Equatable {
    public var provider: CloudProvider
    public init(provider: CloudProvider = .xai) { self.provider = provider }
}

public struct CloudPreferencesStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> CloudPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return CloudPreferences() }
        return try JSONDecoder().decode(CloudPreferences.self, from: Data(contentsOf: url))
    }
    public func save(_ value: CloudPreferences) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

public enum CloudError: String, LocalizedError, Equatable {
    case missingKey, invalidKey, invalidRequest, authentication, quota, unavailable, incomplete, invalidResponse, timeout, network, offline
    public var errorDescription: String? {
        switch self {
        case .missingKey: return "這家服務商還沒有金鑰，請先儲存。"
        case .invalidKey: return "金鑰不能包含空白或換行，請重新貼上。"
        case .invalidRequest: return "API 金鑰、模型或參數不符合服務商要求，請檢查設定。"
        case .authentication: return "金鑰無效或沒有模型權限，請檢查服務商帳戶。"
        case .quota: return "API 額度不足或請求過於頻繁，請檢查服務商帳戶後再試。"
        case .unavailable: return "服務商暫時無法回應，請稍後再試。"
        case .incomplete: return "服務商沒有回傳完整文字，本次沒有套用結果。"
        case .invalidResponse: return "服務商的回覆格式不符合預期。"
        case .timeout: return "連線逾時，請稍後再試。"
        case .network: return "無法連線，請檢查網路。"
        case .offline: return "目前離線，未送出校正。"
        }
    }
}

public enum CloudWire {
    public static var correctionSchema: [String: Any] {
        ["type": "object", "additionalProperties": false, "required": ["corrections", "punctuated"],
         "properties": ["corrections": ["type": "array", "items": [
            "type": "object", "additionalProperties": false, "required": ["from", "to", "occurrence"],
            "properties": ["from": ["type": "string"], "to": ["type": "string"], "occurrence": ["type": "integer"]]
          ]], "punctuated": ["type": ["string", "null"]]]]
    }
    public static func request(_ body: ChatBody, provider: CloudProvider, purpose: CloudPurpose, key: String) throws -> URLRequest {
        guard !key.isEmpty else { throw CloudError.missingKey }
        guard !key.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else { throw CloudError.invalidKey }
        var request = URLRequest(url: provider.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = body.timeoutSeconds.isFinite ? body.timeoutSeconds : TimeInterval(Int32.max)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any]
        let model = provider.model(for: purpose)
        switch provider {
        case .xai:
            var tuned = body; tuned.model = model
            // Preserve the non-reasoning behavior of the retired correction alias.
            if purpose == .correction { tuned.reasoningEffort = "none" }
            payload = tuned.json
            payload["max_tokens"] = 4096
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .openai:
            payload = ["model": model, "instructions": body.system, "input": body.user,
                       "store": false, "max_output_tokens": 4096, "reasoning": ["effort": purpose == .correction ? "low" : "none"]]
            if body.jsonOutput { payload["text"] = ["format": ["type": "json_schema", "name": "corrections", "strict": true, "schema": correctionSchema]] }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            var output: [String: Any] = ["effort": "low"]
            if body.jsonOutput { output["format"] = ["type": "json_schema", "schema": correctionSchema] }
            payload = ["model": model, "system": body.system, "messages": [["role": "user", "content": body.user]],
                       // Haiku 5.5 thinks adaptively by default; low effort alone is not off.
                       "thinking": ["type": "disabled"],
                       "max_tokens": 4096, "output_config": output]
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .google:
            // gemini-3.8-flash accepts low/medium/high only; MINIMAL is rejected with HTTP 400.
            var generation: [String: Any] = ["maxOutputTokens": 4096, "thinkingConfig": ["thinkingLevel": "low"]]
            if body.jsonOutput { generation["responseMimeType"] = "application/json"; generation["responseJsonSchema"] = correctionSchema }
            payload = ["systemInstruction": ["parts": [["text": body.system]]],
                       "contents": [["role": "user", "parts": [["text": body.user]]]], "generationConfig": generation]
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    /// A provider-reported model is evidence, not a guess from the requested ID.
    /// No response text, key, request ID, or personal information is retained here.
    public static func reportedModel(_ data: Data, provider: CloudProvider) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = root[provider == .google ? "modelVersion" : "model"] as? String,
              value.range(of: "^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$", options: .regularExpression) != nil else { return nil }
        return value
    }

    public static func parse(_ data: Data, status: Int, provider: CloudProvider) throws -> String {
        guard (200...299).contains(status) else {
            switch status { case 400, 404: throw CloudError.invalidRequest; case 408: throw CloudError.timeout; case 401, 403: throw CloudError.authentication; case 402, 429: throw CloudError.quota; default: throw CloudError.unavailable }
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CloudError.invalidResponse }
        let text: String
        switch provider {
        case .xai:
            guard let choices = root["choices"] as? [[String: Any]], let first = choices.first,
                  first["finish_reason"] as? String == "stop", let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else { throw CloudError.incomplete }
            text = content
        case .openai:
            guard root["status"] as? String == "completed", let output = root["output"] as? [[String: Any]] else { throw CloudError.incomplete }
            let content = output.filter { $0["type"] as? String == "message" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }
            guard !content.contains(where: { $0["type"] as? String == "refusal" }) else { throw CloudError.incomplete }
            text = content.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined()
        case .anthropic:
            guard root["stop_reason"] as? String == "end_turn", let content = root["content"] as? [[String: Any]] else { throw CloudError.incomplete }
            text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        case .google:
            guard let candidates = root["candidates"] as? [[String: Any]], let first = candidates.first,
                  first["finishReason"] as? String == "STOP", let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { throw CloudError.incomplete }
            text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudError.incomplete }
        return trimmed
    }
}

/// No disk cache, cookies, response-body logging, or cross-host redirects.
public final class CloudClient: NSObject, URLSessionTaskDelegate {
    public static let shared = CloudClient()
    private let session: URLSession
    private let transport: PrivateHTTPDelegate
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = nil; config.urlCache = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = TimeInterval(Int32.max)
        config.timeoutIntervalForResource = TimeInterval(Int32.max)
        let delegate = PrivateHTTPDelegate()
        transport = delegate
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        super.init()
    }
    deinit { session.invalidateAndCancel() }
    /// Opens a TLS connection to the host root. No key, body, or retained response.
    public func prewarm(_ url: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.httpBody = nil
        request.timeoutInterval = 5
        session.dataTask(with: request) { _, _, _ in }.resume()
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    public func complete(_ body: ChatBody, provider: CloudProvider, purpose: CloudPurpose, key: String,
                         cancellation: ProcessingCancellation? = nil, onModel: ((String?) -> Void)? = nil,
                         onTimings: ((TranscriptionTransferTimings?) -> Void)? = nil) throws -> String {
        try cancellation?.check()
        let request = try CloudWire.request(body, provider: provider, purpose: purpose, key: key)
        let semaphore = DispatchSemaphore(value: 0)
        let box = CloudResultBox()
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                box.value = .failure((error as? URLError)?.code == .timedOut ? CloudError.timeout : CloudError.network)
            } else if let http = response as? HTTPURLResponse, let data {
                box.value = Result {
                    let text = try CloudWire.parse(data, status: http.statusCode, provider: provider)
                    if cancellation?.isCancelled != true { onModel?(CloudWire.reportedModel(data, provider: provider)) }
                    return text
                }
            } else { box.value = .failure(CloudError.invalidResponse) }
            semaphore.signal()
        }
        transport.track(task, progress: nil)
        defer { onTimings?(transport.finish(task)) }
        let registration = cancellation?.register { task.cancel(); semaphore.signal() }
        defer { cancellation?.unregister(registration) }
        try cancellation?.check()
        task.resume()
        if body.timeoutSeconds.isFinite {
            guard semaphore.wait(timeout: .now() + body.timeoutSeconds + 1) == .success else { task.cancel(); throw CloudError.timeout }
        } else {
            semaphore.wait()
        }
        if cancellation?.didSkipCloud == true { throw ProcessingError.skippedCloud }
        try cancellation?.check()
        return try box.value.get()
    }
}

private final class CloudResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<String, Error> = .failure(CloudError.network)
    var value: Result<String, Error> { get { lock.lock(); defer { lock.unlock() }; return result } set { lock.lock(); defer { lock.unlock() }; result = newValue } }
}
