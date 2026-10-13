import XCTest
@testable import EdgelessTypeCore

final class TranscriptionTests: XCTestCase {
    private var fixtureAudio: Data { Data("RIFF0000WAVE".utf8) + Data(repeating: 1, count: 100) }
    private var enabled: TranscriptionPreferences { .init(backend: .openAI, cloudAudioConsent: true) }

    func testMissingSettingsDefaultToLocalAndNeverRunCloudClosure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TranscriptionPreferencesStore(url: root.appendingPathComponent("transcription.json"))
        let preferences = try store.load()
        XCTAssertEqual(preferences, TranscriptionPreferences())
        var local = 0, cloud = 0
        let result = try TranscriptionRouter.run(preferences, local: { local += 1; return "本機" }, cloud: { cloud += 1; return "雲端" })
        XCTAssertEqual(result, "本機"); XCTAssertEqual(local, 1); XCTAssertEqual(cloud, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }
    func testCloudCannotRunOrSaveWithoutExplicitConsent() {
        let preferences = TranscriptionPreferences(backend: .openAI)
        var called = false
        XCTAssertThrowsError(try TranscriptionRouter.run(preferences, local: { called = true; return "local" }, cloud: { called = true; return "cloud" }))
        XCTAssertFalse(called)
        XCTAssertThrowsError(try OpenAITranscriptionWire.request(audio: fixtureAudio, preferences: preferences, key: "fixture"))
        XCTAssertThrowsError(try OpenAITranscriptionWire.request(audio: fixtureAudio, preferences: .init(), key: "fixture"))
    }
    func testSettingsRoundTripAndCloudFailureDoesNotFallBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TranscriptionPreferencesStore(url: root.appendingPathComponent("transcription.json"))
        try store.save(enabled); XCTAssertEqual(try store.load(), enabled)
        XCTAssertThrowsError(try store.save(.init(backend: .openAI)))
        XCTAssertEqual(try store.load(), enabled)
        var local = 0, cloud = 0
        XCTAssertThrowsError(try TranscriptionRouter.run(enabled, local: { local += 1; return "local" }, cloud: { cloud += 1; throw CloudError.quota }))
        XCTAssertEqual(local, 0); XCTAssertEqual(cloud, 1)
        try store.save(.init()); XCTAssertEqual(try store.load().backend, .localWhisper)
    }
    func testCorruptOrIncompleteCloudSettingsDoNotAuthorizeUpload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = TranscriptionPreferencesStore(url: root.appendingPathComponent("transcription.json"))
        for text in ["broken", #"{"backend":"openAI"}"#, #"{"backend":"unknown","cloudAudioConsent":true}"#, #"{"backend":"openAI","cloudAudioConsent":false}"#] {
            try Data(text.utf8).write(to: store.url)
            XCTAssertThrowsError(try store.load())
        }
    }
    func testMultipartUsesFixedOpenAIEndpointAndGenericFilename() throws {
        let request = try OpenAITranscriptionWire.request(audio: fixtureAudio, preferences: enabled, key: "fixture-key")
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("gpt-transcribe")); XCTAssertTrue(body.contains("filename=\"recording.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertFalse(body.contains("fixture-key")); XCTAssertFalse(body.contains("/Users/"))
        XCTAssertFalse(body.contains("response_format")); XCTAssertFalse(body.contains("name=\"language\""))
        let type = request.value(forHTTPHeaderField: "Content-Type")!
        let boundary = String(type.split(separator: "=").last!)
        XCTAssertTrue(body.hasSuffix("\r\n--" + boundary + "--\r\n"))
    }
    func testOversizedInvalidAudioAndBadKeyFailBeforeSending() {
        XCTAssertThrowsError(try OpenAITranscriptionWire.request(audio: Data(), preferences: enabled, key: "fixture"))
        XCTAssertThrowsError(try OpenAITranscriptionWire.request(audio: Data(repeating: 1, count: OpenAITranscriptionWire.maximumAudioBytes + 1), preferences: enabled, key: "fixture"))
        XCTAssertThrowsError(try OpenAITranscriptionWire.request(audio: fixtureAudio, preferences: enabled, key: ""))
        XCTAssertThrowsError(try OpenAITranscriptionWire.request(audio: fixtureAudio, preferences: enabled, key: "fixture\nkey"))
    }
    func testResponseConversionEmptySpeechAndSanitizedFailures() throws {
        XCTAssertEqual(try OpenAITranscriptionWire.parse(Data(#"{"text":"这是语音识别结果。"}"#.utf8), status: 200), "這是語音識別結果。")
        XCTAssertEqual(try OpenAITranscriptionWire.parse(Data(#"{"text":"  "}"#.utf8), status: 200), "")
        for status in [400, 401, 403, 402, 429, 408, 413, 500] {
            XCTAssertThrowsError(try OpenAITranscriptionWire.parse(Data("private-provider-message".utf8), status: status)) { error in
                XCTAssertFalse(error.localizedDescription.contains("private-provider-message"))
            }
        }
        for body in ["{}", "[]", #"{"text":12}"#, #"{"text":"partial","error":{}}"#] {
            XCTAssertThrowsError(try OpenAITranscriptionWire.parse(Data(body.utf8), status: 200))
        }
    }
    func testRealClientUsesMockTransportAndBlocksRedirects() throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TranscriptionFixtureProtocol.self]
        TranscriptionFixtureProtocol.calls = 0
        let client = OpenAITranscriptionClient(configuration: config)
        XCTAssertThrowsError(try client.transcribe(audio: fixtureAudio, preferences: .init(), key: "fixture"))
        XCTAssertEqual(TranscriptionFixtureProtocol.calls, 0)
        XCTAssertEqual(try client.transcribe(audio: fixtureAudio, preferences: enabled, key: "fixture"), "固定轉寫文字。")
        XCTAssertEqual(TranscriptionFixtureProtocol.calls, 1)
        var progress: [Double] = []
        XCTAssertEqual(try client.transcribe(audio: fixtureAudio, preferences: enabled, key: "second-fixture", onProgress: { progress.append($0) }), "固定轉寫文字。")
        XCTAssertEqual(TranscriptionFixtureProtocol.calls, 2)
        XCTAssertEqual(progress.first, 0)

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let request = URLRequest(url: URL(string: "https://example.com/redirect")!)
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var allowed = true
        client.urlSession(session, task: session.dataTask(with: request), willPerformHTTPRedirection: response, newRequest: request) { allowed = $0 != nil }
        XCTAssertFalse(allowed)
    }
}

private final class TranscriptionFixtureProtocol: URLProtocol {
    static var calls = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"text":"固定转写文字。"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
