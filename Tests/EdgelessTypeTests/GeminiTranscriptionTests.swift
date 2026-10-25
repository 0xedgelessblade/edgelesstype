import XCTest
@testable import EdgelessTypeCore

final class GeminiTranscriptionTests: XCTestCase {
    private var fixtureAudio: Data { Data("RIFF0000WAVE".utf8) + Data(repeating: 1, count: 100) }
    private func enabled(_ backend: TranscriptionBackend) -> TranscriptionPreferences { .init(backend: backend, cloudAudioConsent: true) }
    private struct MissingValue: Error {}
    private func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw MissingValue() }; return value }
    private func json(_ request: URLRequest) throws -> [String: Any] {
        try unwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
    }

    func testBackendMetadataAndConsentRules() throws {
        XCTAssertEqual(TranscriptionBackend.allCases, [.localWhisper, .openAI, .geminiTranscribe, .geminiDirect])
        XCTAssertEqual(TranscriptionBackend.geminiTranscribe.cloudProvider, .google)
        XCTAssertEqual(TranscriptionBackend.geminiDirect.cloudProvider, .google)
        XCTAssertNil(TranscriptionBackend.localWhisper.cloudProvider)
        XCTAssertTrue(TranscriptionBackend.geminiDirect.mergesCorrection)
        XCTAssertFalse(TranscriptionBackend.geminiTranscribe.mergesCorrection)
        XCTAssertEqual(TranscriptionBackend.geminiTranscribe.cloudModel, "gemini-3.5-transcribe")
        XCTAssertEqual(TranscriptionBackend.geminiDirect.cloudModel, "gemini-3.8-flash")
        for backend in [TranscriptionBackend.geminiTranscribe, .geminiDirect] {
            XCTAssertThrowsError(try TranscriptionPreferences(backend: backend).validated())
            XCTAssertEqual(try enabled(backend).validated().backend, backend)
            var cloud = 0
            XCTAssertEqual(try TranscriptionRouter.run(enabled(backend), local: { "local" }, cloud: { cloud += 1; return "cloud" }), "cloud")
            XCTAssertEqual(cloud, 1)
            XCTAssertThrowsError(try GeminiAudioWire.request(audio: fixtureAudio, backend: backend, preferences: .init(backend: backend), key: "fixture"))
        }
        // Stored settings for a Gemini backend without consent never authorize an upload.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = TranscriptionPreferencesStore(url: root.appendingPathComponent("transcription.json"))
        try Data(#"{"backend":"geminiDirect","cloudAudioConsent":false}"#.utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
        try store.save(enabled(.geminiTranscribe)); XCTAssertEqual(try store.load(), enabled(.geminiTranscribe))
    }

    func testAudioRequestsGiveUpOnStalledRepliesInsteadOfSpinning() throws {
        XCTAssertEqual(AudioUploadPolicy.responseTimeout(audioBytes: 44 + 16 * 32_000), 19)
        XCTAssertEqual(AudioUploadPolicy.responseTimeout(audioBytes: 44 + 3_600 * 32_000), 180)
        for backend in [TranscriptionBackend.geminiTranscribe, .geminiDirect] {
            let request = try GeminiAudioWire.request(audio: fixtureAudio, backend: backend, preferences: enabled(backend), key: "fixture")
            XCTAssertTrue(request.timeoutInterval <= 16)
        }
    }

    func testTranscribeRequestUsesInteractionsEndpointSmartModeAndVocabulary() throws {
        let request = try GeminiAudioWire.request(audio: fixtureAudio, backend: .geminiTranscribe, preferences: enabled(.geminiTranscribe), key: "fixture-key",
                                                  terms: [" 權限 ", "", "權限", "Hermes"], context: "CONTEXT_FIXTURE_ONLY")
        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/interactions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(request.url!.absoluteString.contains("fixture-key"))
        let body = try json(request)
        XCTAssertEqual(body["model"] as? String, "gemini-3.5-transcribe")
        let input = try unwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        XCTAssertEqual(input[0]["type"] as? String, "audio")
        XCTAssertEqual(input[0]["mime_type"] as? String, "audio/wav")
        XCTAssertEqual(input[0]["data"] as? String, fixtureAudio.base64EncodedString())
        let config = try unwrap((body["generation_config"] as? [String: Any])?["transcription_config"] as? [String: Any])
        XCTAssertEqual(config["mode"] as? String, "smart")
        XCTAssertEqual(config["custom_vocabulary"] as? [String], ["權限", "Hermes"])
        XCTAssertNil(config["language_codes"])
        let text = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertFalse(text.contains("fixture-key")); XCTAssertFalse(text.contains("CONTEXT_FIXTURE_ONLY")); XCTAssertFalse(text.contains("/Users/"))
        // No vocabulary → no custom_vocabulary field at all.
        let plain = try json(try GeminiAudioWire.request(audio: fixtureAudio, backend: .geminiTranscribe, preferences: enabled(.geminiTranscribe), key: "k"))
        XCTAssertNil(((plain["generation_config"] as? [String: Any])?["transcription_config"] as? [String: Any])?["custom_vocabulary"])
    }

    func testDirectRequestUsesGenerateContentWithLowThinkingAndInlineAudio() throws {
        let preferences = TranscriptionPreferences(backend: .geminiDirect, cloudAudioConsent: true, recordingContextEnabled: true, cloudContextConsent: true)
        let request = try GeminiAudioWire.request(audio: fixtureAudio, backend: .geminiDirect, preferences: preferences, key: "fixture-key",
                                                  terms: ["權限"], context: "CONTEXT_FIXTURE_ONLY")
        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
        let body = try json(request)
        let generation = try unwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual((generation["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "low")
        XCTAssertNil(generation["responseMimeType"])
        let system = try unwrap(((body["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(system.contains("繁體")); XCTAssertTrue(system.contains(ContextCorrection.speechRepairGuidance))
        let parts = try unwrap(((body["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]]))
        XCTAssertEqual(parts.count, 2)
        let inline = try unwrap(parts[0]["inlineData"] as? [String: Any])
        XCTAssertEqual(inline["mimeType"] as? String, "audio/wav")
        XCTAssertEqual(inline["data"] as? String, fixtureAudio.base64EncodedString())
        let user = try unwrap(parts[1]["text"] as? String)
        XCTAssertTrue(user.contains("權限")); XCTAssertTrue(user.contains("CONTEXT_FIXTURE_ONLY"))
        // Context travels only with both the capture switch and cloud-context consent.
        for settings in [TranscriptionPreferences(backend: .geminiDirect, cloudAudioConsent: true, recordingContextEnabled: true, cloudContextConsent: false),
                         TranscriptionPreferences(backend: .geminiDirect, cloudAudioConsent: true, recordingContextEnabled: false, cloudContextConsent: true)] {
            let withheld = try GeminiAudioWire.request(audio: fixtureAudio, backend: .geminiDirect, preferences: settings, key: "k", context: "CONTEXT_FIXTURE_ONLY")
            XCTAssertFalse(String(decoding: withheld.httpBody!, as: UTF8.self).contains("CONTEXT_FIXTURE_ONLY"))
        }
        // A backend mismatch between the request and the saved choice is refused.
        XCTAssertThrowsError(try GeminiAudioWire.request(audio: fixtureAudio, backend: .geminiDirect, preferences: enabled(.geminiTranscribe), key: "k"))
        XCTAssertThrowsError(try GeminiAudioWire.request(audio: fixtureAudio, backend: .openAI, preferences: enabled(.openAI), key: "k"))
    }

    func testOversizedInvalidAudioAndBadKeyFailBeforeSending() {
        for backend in [TranscriptionBackend.geminiTranscribe, .geminiDirect] {
            XCTAssertThrowsError(try GeminiAudioWire.request(audio: Data(), backend: backend, preferences: enabled(backend), key: "fixture"))
            XCTAssertThrowsError(try GeminiAudioWire.request(audio: Data(repeating: 1, count: GeminiAudioWire.maximumAudioBytes + 1), backend: backend, preferences: enabled(backend), key: "fixture")) { error in
                XCTAssertEqual(error as? TranscriptionError, .audioTooLarge)
            }
            XCTAssertThrowsError(try GeminiAudioWire.request(audio: fixtureAudio, backend: backend, preferences: enabled(backend), key: ""))
            XCTAssertThrowsError(try GeminiAudioWire.request(audio: fixtureAudio, backend: backend, preferences: enabled(backend), key: "fixture\nkey"))
        }
        // Inline base64 must stay under the 20 MB request limit.
        XCTAssertTrue(Double(GeminiAudioWire.maximumAudioBytes) * 4 / 3 < 20_000_000)
    }

    func testTranscribeResponseParsingAndSanitizedFailures() throws {
        let completed = #"{"id":"interactions/x","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"这是语音识别结果，"},{"type":"other","text":"ignored"},{"type":"text","text":"然后 check the settings。"}]}]}"#
        XCTAssertEqual(try GeminiAudioWire.parse(Data(completed.utf8), status: 200, backend: .geminiTranscribe), "這是語音識別結果，然後 check the settings。")
        XCTAssertEqual(try GeminiAudioWire.parse(Data(#"{"status":"completed","steps":[]}"#.utf8), status: 200, backend: .geminiTranscribe), "")
        for body in [#"{"status":"in_progress","steps":[]}"#, #"{"steps":[]}"#, "[]", "{}", #"{"status":"completed","steps":[],"error":{}}"#] {
            XCTAssertThrowsError(try GeminiAudioWire.parse(Data(body.utf8), status: 200, backend: .geminiTranscribe))
        }
        for status in [400, 401, 403, 402, 429, 408, 413, 500] {
            XCTAssertThrowsError(try GeminiAudioWire.parse(Data("private-provider-message".utf8), status: status, backend: .geminiTranscribe)) { error in
                XCTAssertFalse(error.localizedDescription.contains("private-provider-message"))
            }
        }
        XCTAssertThrowsError(try GeminiAudioWire.parse(Data("private-provider-message".utf8), status: 413, backend: .geminiDirect)) { error in
            XCTAssertEqual(error as? TranscriptionError, .audioTooLarge)
        }
    }

    func testDirectResponseIgnoresThoughtsAndRequiresStop() throws {
        let stop = #"{"modelVersion":"gemini-3.8-flash","candidates":[{"finishReason":"STOP","content":{"parts":[{"thought":true,"text":"ignored"},{"text":"请打开麦克风的权限。"}]}}]}"#
        XCTAssertEqual(try GeminiAudioWire.parse(Data(stop.utf8), status: 200, backend: .geminiDirect), "請打開麥克風的權限。")
        XCTAssertEqual(GeminiAudioWire.reportedModel(Data(stop.utf8)), "gemini-3.8-flash")
        XCTAssertEqual(try GeminiAudioWire.parse(Data(#"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"  "}]}}]}"#.utf8), status: 200, backend: .geminiDirect), "")
        for body in [#"{"candidates":[{"finishReason":"SAFETY","content":{"parts":[{"text":"partial"}]}}]}"#,
                     #"{"candidates":[{"finishReason":"MAX_TOKENS","content":{"parts":[{"text":"partial"}]}}]}"#,
                     #"{"candidates":[]}"#, "{}", #"{"error":{"message":"private"}}"#] {
            XCTAssertThrowsError(try GeminiAudioWire.parse(Data(body.utf8), status: 200, backend: .geminiDirect))
        }
        XCTAssertNil(GeminiAudioWire.reportedModel(Data(#"{"modelVersion":"bad value with spaces"}"#.utf8)))
    }

    func testClientUsesMockTransportReportsModelAndBlocksRedirects() throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [GeminiFixtureProtocol.self]
        GeminiFixtureProtocol.calls = 0
        let client = CloudAudioClient(configuration: config)
        XCTAssertThrowsError(try client.transcribeGemini(audio: fixtureAudio, backend: .geminiDirect, preferences: .init(backend: .geminiDirect), key: "fixture"))
        XCTAssertEqual(GeminiFixtureProtocol.calls, 0)
        var reported: String?
        var progress: [Double] = []
        XCTAssertEqual(try client.transcribeGemini(audio: fixtureAudio, backend: .geminiDirect, preferences: enabled(.geminiDirect), key: "fixture",
                                                   onProgress: { progress.append($0) }, onModel: { reported = $0 }), "固定轉寫文字。")
        XCTAssertEqual(GeminiFixtureProtocol.calls, 1)
        XCTAssertEqual(reported, "gemini-3.8-flash")
        XCTAssertEqual(progress.first, 0)
        GeminiFixtureProtocol.transcribe = true
        XCTAssertEqual(try client.transcribeGemini(audio: fixtureAudio, backend: .geminiTranscribe, preferences: enabled(.geminiTranscribe), key: "fixture"), "固定轉寫文字。")
        GeminiFixtureProtocol.transcribe = false
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://example.com/redirect")!)
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var allowed = true
        client.urlSession(session, task: session.dataTask(with: request), willPerformHTTPRedirection: response, newRequest: request) { allowed = $0 != nil }
        XCTAssertFalse(allowed)
    }
}

private final class GeminiFixtureProtocol: URLProtocol {
    static var calls = 0
    static var transcribe = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = Self.transcribe
            ? #"{"status":"completed","steps":[{"content":[{"type":"text","text":"固定转写文字。"}]}]}"#
            : #"{"modelVersion":"gemini-3.8-flash","candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"固定转写文字。"}]}}]}"#
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
