import XCTest
@testable import EdgelessTypeCore

final class LiveTranscriptionTests: XCTestCase {
    final class ScriptedSocket: LiveSocket {
        private let lock = NSLock()
        private var sentMessages: [[String: Any]] = []
        private var waiting: ((Result<Data, Error>) -> Void)?
        private var queued: [Result<Data, Error>] = []
        var closed = false
        var refusedStatus: Int?
        var sent: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return sentMessages }
        func send(_ text: String) {
            let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
            lock.lock(); sentMessages.append(object); lock.unlock()
        }
        func receive(_ completion: @escaping (Result<Data, Error>) -> Void) {
            lock.lock()
            if queued.isEmpty { waiting = completion; lock.unlock() }
            else { let next = queued.removeFirst(); lock.unlock(); completion(next) }
        }
        func close() { closed = true }
        func push(_ json: String) { deliver(.success(Data(json.utf8))) }
        func fail() { deliver(.failure(CloudError.network)) }
        private func deliver(_ value: Result<Data, Error>) {
            lock.lock()
            if let completion = waiting { waiting = nil; lock.unlock(); completion(value) }
            else { queued.append(value); lock.unlock() }
        }
        /// Order of what left the socket: setup, start, audio byte counts, end.
        var trace: [String] {
            sent.map { message in
                if message["setup"] != nil { return "setup" }
                let input = message["realtimeInput"] as? [String: Any] ?? [:]
                if input["activityStart"] != nil { return "start" }
                if input["activityEnd"] != nil { return "end" }
                let data = (input["audio"] as? [String: Any])?["data"] as? String ?? ""
                return "audio:\(Data(base64Encoded: data)?.count ?? -1)"
            }
        }
    }

    private func settle(_ session: LiveTranscriptionSession) { for _ in 0..<4 { session.drain() } }
    private let ready = #"{"setupComplete":{}}"#
    private let done = #"{"serverContent":{"generationComplete":true}}"#
    private func final(_ text: String) -> String { #"{"serverContent":{"inputTranscription":{"text":"\#(text)"}}}"# }

    func testRequestKeepsTheKeyOutOfTheURL() throws {
        let request = try GeminiLiveWire.request(key: "synthetic-key")
        XCTAssertEqual(request.url?.scheme, "wss")
        XCTAssertEqual(request.url?.host, "generativelanguage.googleapis.com")
        XCTAssertNil(request.url?.query)
        XCTAssertFalse(request.url!.absoluteString.contains("synthetic-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "synthetic-key")
        XCTAssertThrowsError(try GeminiLiveWire.request(key: ""))
        XCTAssertThrowsError(try GeminiLiveWire.request(key: "two words"))
    }

    func testSetupUsesManualActivityAndSendsOnlyDictionaryWords() {
        let setup = GeminiLiveWire.setup(terms: ["EdgelessType", " ", "EdgelessType"])["setup"] as! [String: Any]
        XCTAssertEqual(setup["model"] as? String, "models/gemini-3.5-transcribe-live")
        let transcription = setup["inputAudioTranscription"] as! [String: Any]
        XCTAssertEqual(transcription["customVocabulary"] as? [String], ["EdgelessType"])
        XCTAssertEqual((transcription["languageCodes"] as? [String])?.count, 0)
        let detection = (setup["realtimeInputConfig"] as! [String: Any])["automaticActivityDetection"] as! [String: Any]
        XCTAssertEqual(detection["disabled"] as? Bool, true)
        let empty = GeminiLiveWire.setup(terms: [])["setup"] as! [String: Any]
        XCTAssertNil((empty["inputAudioTranscription"] as! [String: Any])["customVocabulary"])
    }

    func testEventsIgnoreInterimTextAndRecogniseBothEndings() {
        XCTAssertEqual(GeminiLiveWire.events(Data(ready.utf8)), [.ready])
        XCTAssertEqual(GeminiLiveWire.events(Data(#"{"serverContent":{"interimInputTranscription":{"text":"half"}}}"#.utf8)), [])
        XCTAssertEqual(GeminiLiveWire.events(Data(final("合成文字").utf8)), [.final("合成文字")])
        XCTAssertEqual(GeminiLiveWire.events(Data(done.utf8)), [.finished])
        XCTAssertEqual(GeminiLiveWire.events(Data(#"{"serverContent":{},"voiceActivity":{"type":"ACTIVITY_END"}}"#.utf8)), [.finished])
        XCTAssertEqual(GeminiLiveWire.events(Data(#"{"serverContent":{},"voiceActivity":{"type":"ACTIVITY_START"}}"#.utf8)), [])
        XCTAssertEqual(GeminiLiveWire.events(Data("not json".utf8)), [])
    }

    func testAudioSpokenBeforeTheServerIsReadyIsSentInOrder() throws {
        let socket = ScriptedSocket()
        let session = LiveTranscriptionSession(socket: socket, terms: [])
        session.append(Data(repeating: 1, count: 5000))
        settle(session)
        XCTAssertEqual(socket.trace, ["setup"])
        socket.push(ready); settle(session)
        XCTAssertEqual(socket.trace, ["setup", "start", "audio:3200"])
        session.append(Data(repeating: 2, count: 1500)); settle(session)
        XCTAssertEqual(socket.trace, ["setup", "start", "audio:3200", "audio:3200"])
        session.finish(); settle(session)
        XCTAssertEqual(socket.trace, ["setup", "start", "audio:3200", "audio:3200", "audio:100", "end"])
        socket.push(final("第一段")); socket.push(final("第二段")); socket.push(done); settle(session)
        XCTAssertEqual(try session.waitForText(timeout: 1), "第一段第二段")
        XCTAssertTrue(socket.closed)
        XCTAssertNotNil(session.connectSeconds)
        XCTAssertNotNil(session.finalSeconds)
    }

    func testReleaseBeforeTheServerIsReadyStillSendsEverything() throws {
        let socket = ScriptedSocket()
        let session = LiveTranscriptionSession(socket: socket, terms: [])
        session.append(Data(repeating: 1, count: 4000))
        session.finish(); settle(session)
        XCTAssertEqual(socket.trace, ["setup"])
        socket.push(ready); settle(session)
        XCTAssertEqual(socket.trace, ["setup", "start", "audio:3200", "audio:800", "end"])
        socket.push(final("短句")); socket.push(done); settle(session)
        XCTAssertEqual(try session.waitForText(timeout: 1), "短句")
    }

    func testAPauseWhileTheKeyIsHeldDoesNotEndTheRecording() throws {
        let socket = ScriptedSocket()
        let session = LiveTranscriptionSession(socket: socket, terms: [])
        socket.push(ready); socket.push(final("前半")); socket.push(done); settle(session)
        XCTAssertFalse(socket.closed)
        session.finish(); settle(session)
        socket.push(final("後半")); socket.push(done); settle(session)
        XCTAssertEqual(try session.waitForText(timeout: 1), "前半後半")
    }

    func testRecordingWithoutSpeechEndsEmptyInsteadOfTimingOut() throws {
        let socket = ScriptedSocket()
        let session = LiveTranscriptionSession(socket: socket, terms: [])
        socket.push(ready); settle(session)
        session.finish(); settle(session)
        socket.push(#"{"serverContent":{},"voiceActivity":{"type":"ACTIVITY_END"}}"#); settle(session)
        XCTAssertEqual(try session.waitForText(timeout: 1), "")
    }

    func testBrokenConnectionAndRefusedKeyBecomeCloudErrors() {
        let dropped = ScriptedSocket()
        let first = LiveTranscriptionSession(socket: dropped, terms: [])
        dropped.fail(); settle(first)
        XCTAssertThrowsError(try first.waitForText(timeout: 1)) { XCTAssertEqual($0 as? CloudError, .network) }
        let refused = ScriptedSocket(); refused.refusedStatus = 403
        let second = LiveTranscriptionSession(socket: refused, terms: [])
        refused.fail(); settle(second)
        XCTAssertThrowsError(try second.waitForText(timeout: 1)) { XCTAssertEqual($0 as? CloudError, .authentication) }
    }

    func testSilentServerTimesOutAndSkippingTheCloudStopsTheWait() {
        let socket = ScriptedSocket()
        let session = LiveTranscriptionSession(socket: socket, terms: [])
        socket.push(ready); session.finish(); settle(session)
        XCTAssertThrowsError(try session.waitForText(timeout: 0.05)) { XCTAssertEqual($0 as? CloudError, .timeout) }
        settle(session)
        XCTAssertTrue(socket.closed)
        let other = ScriptedSocket()
        let waiting = LiveTranscriptionSession(socket: other, terms: [])
        let token = ProcessingCancellation(); token.skipCloud()
        XCTAssertThrowsError(try waiting.waitForText(timeout: 5, cancellation: token)) { XCTAssertTrue($0 is ProcessingError) }
    }

    func testLiveBackendUsesTheGoogleKeyAndUploadsAsTranscribeWhenItFallsBack() {
        XCTAssertTrue(TranscriptionBackend.geminiLive.isCloud)
        XCTAssertTrue(TranscriptionBackend.geminiLive.streamsWhileRecording)
        XCTAssertFalse(TranscriptionBackend.geminiLive.mergesCorrection)
        XCTAssertEqual(TranscriptionBackend.geminiLive.cloudProvider, .google)
        XCTAssertEqual(TranscriptionBackend.geminiLive.uploadBackend, .geminiTranscribe)
        XCTAssertEqual(TranscriptionBackend.geminiDirect.uploadBackend, .geminiDirect)
        XCTAssertThrowsError(try TranscriptionPreferences(backend: .geminiLive).validated())
    }
}
