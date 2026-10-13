import XCTest
@testable import EdgelessTypeCore

final class RecordingContextTests: XCTestCase {
    func testOldSettingsNeverEnableCaptureOrCloudSharing() throws {
        let old = Data(#"{"backend":"localWhisper","cloudAudioConsent":false}"#.utf8)
        let decoded = try JSONDecoder().decode(TranscriptionPreferences.self, from: old)
        XCTAssertFalse(decoded.recordingContextEnabled)
        XCTAssertFalse(decoded.cloudContextConsent)
        XCTAssertFalse(decoded.capturesRecordingContext)
    }
    func testContextConsentMatrix() throws {
        for backend in TranscriptionBackend.allCases {
            for enabled in [false, true] {
                for cloud in [false, true] {
                    let settings = TranscriptionPreferences(backend: backend, cloudAudioConsent: true, recordingContextEnabled: enabled, cloudContextConsent: cloud)
                    XCTAssertEqual(settings.capturesRecordingContext, enabled && (backend == .localWhisper || cloud))
                    XCTAssertEqual(try JSONDecoder().decode(TranscriptionPreferences.self, from: JSONEncoder().encode(settings)), settings)
                }
            }
        }
        XCTAssertFalse(TranscriptionPreferences(backend: .openAI, recordingContextEnabled: true, cloudContextConsent: true).capturesRecordingContext)
    }
    func testSecureUnknownAndNonTextFieldsAreSkipped() {
        XCTAssertFalse(RecordingContext.allowsField(role: "AXTextField", subrole: "AXSecureTextField", protected: false))
        XCTAssertFalse(RecordingContext.allowsField(role: "AXTextArea", subrole: nil, protected: true))
        XCTAssertFalse(RecordingContext.allowsField(role: "AXTextField", subrole: nil, protected: false))
        XCTAssertFalse(RecordingContext.allowsField(role: "AXWebArea", subrole: "", protected: false))
        XCTAssertTrue(RecordingContext.allowsField(role: "AXTextArea", subrole: nil, protected: false))
    }
    func testContextReadsOnlyBoundedCursorRange() {
        XCTAssertEqual(RecordingContext.range(cursor: 500, count: 10000), NSRange(location: 380, length: 160))
        XCTAssertEqual(RecordingContext.range(cursor: 10, count: 15), NSRange(location: 0, length: 15))
        XCTAssertNil(RecordingContext.range(cursor: -1, count: 10))
        XCTAssertNil(RecordingContext.range(cursor: 11, count: 10))
        XCTAssertNil(RecordingContext.range(cursor: 0, count: 0))
    }
    func testLateContextCannotReachFinishedOrNextRecording() {
        let old = RecordingContext(), next = RecordingContext()
        XCTAssertNil(old.take())
        old.supply("old fixture")
        next.supply("new fixture")
        XCTAssertNil(old.take())
        XCTAssertEqual(next.take(), "new fixture")
        XCTAssertNil(next.take())
    }
    func testDiscardAndLengthLimit() {
        let capture = RecordingContext()
        capture.supply(String(repeating: "a", count: 300))
        XCTAssertEqual(capture.take()?.count, 160)
        let cancelled = RecordingContext()
        cancelled.supply("fixture"); cancelled.discard()
        XCTAssertNil(cancelled.take())
        XCTAssertEqual(RecordingContext.prompt(terms: "terms", context: nil), "terms")
    }
    func testCloudWireDoesNotLeakContextWithoutBothSwitches() throws {
        var audio = Data("RIFF".utf8); audio.append(Data(repeating: 0, count: 4)); audio.append(Data("WAVE".utf8)); audio.append(Data(repeating: 0, count: 64))
        for enabled in [false, true] {
            for cloud in [false, true] {
                let settings = TranscriptionPreferences(backend: .openAI, cloudAudioConsent: true, recordingContextEnabled: enabled, cloudContextConsent: cloud)
                let request = try OpenAITranscriptionWire.request(audio: audio, preferences: settings, key: "fixture", context: "CONTEXT_FIXTURE_ONLY")
                let body = String(decoding: request.httpBody!, as: UTF8.self)
                XCTAssertEqual(body.contains("CONTEXT_FIXTURE_ONLY"), enabled && cloud)
                XCTAssertEqual(request.url?.host, "api.openai.com")
            }
        }
    }
}
