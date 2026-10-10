import XCTest
@testable import OpenTypelessCore

final class OpenTypelessTests: XCTestCase {
    func testFnTapStartsAndStopsDictation() {
        XCTAssertEqual(Hotkey.decide(session: .idle, tap: .fn), .startDictation)
        XCTAssertEqual(Hotkey.decide(session: .dictation, tap: .fn), .stopDictation)
    }

    func testFnShiftStartsTranslationAndLoneFnEndsIt() {
        XCTAssertEqual(Hotkey.decide(session: .idle, tap: .fnShift), .startTranslation)
        XCTAssertEqual(Hotkey.decide(session: .translation, tap: .fn), .stopTranslation)
        XCTAssertEqual(Hotkey.decide(session: .translation, tap: .fnShift), .ignore)
    }

    func testHoldDoesNothing() {
        let hold = FnGesture(duration: 2.0, shiftDuring: false)
        XCTAssertNil(Hotkey.classify(hold))
        let chordHold = FnGesture(duration: 1.4, shiftDuring: true)
        XCTAssertNil(Hotkey.classify(chordHold))
    }

    func testShortPressClassifies() {
        XCTAssertEqual(Hotkey.classify(FnGesture(duration: 0.2, shiftDuring: false)), .fn)
        XCTAssertEqual(Hotkey.classify(FnGesture(duration: 0.2, shiftDuring: true)), .fnShift)
    }

    func testDictationPastesRoughAndTranslationDoesNot() {
        XCTAssertEqual(Policy.plan(mode: .dictation, transcript: "今天很好。", polishEnabled: false), .pasteRough("今天很好。"))
        XCTAssertEqual(
            Policy.plan(mode: .translation, transcript: "今天很好", polishEnabled: true),
            .waitForEnglish(chinese: "今天很好")
        )
        XCTAssertEqual(Policy.plan(mode: .dictation, transcript: "   ", polishEnabled: true), .drop("沒有聽到字"))
    }

    func testPolishIsFastModelWithoutReasoning() {
        let body = ChatDraft.polish(text: "嗯那個今天")
        XCTAssertEqual(body.model, "grok-4.3")
        XCTAssertNil(body.reasoningEffort)
        XCTAssertFalse(body.sendsAudio)
        XCTAssertFalse(body.json.keys.contains("audio"))
        XCTAssertEqual(body.timeoutSeconds, 1.2)
    }

    func testTranslationUsesSlowerFluentModel() {
        let body = ChatDraft.translate(text: "我想把這句說順")
        XCTAssertEqual(body.model, "grok-4.7")
        XCTAssertEqual(body.reasoningEffort, "high")
        XCTAssertGreaterThan(body.timeoutSeconds, 5)
        XCTAssertFalse(body.sendsAudio)
        XCTAssertTrue(body.system.contains("fluent"))
    }

    func testNeedsPolishSkipsCleanLine() {
        XCTAssertFalse(Policy.needsPolish("今天很好。"))
        XCTAssertTrue(Policy.needsPolish("嗯那個今天"))
        XCTAssertFalse(Policy.shouldCallPolish(transcript: "今天很好。", polishEnabled: true))
        XCTAssertFalse(Policy.shouldCallPolish(transcript: "嗯那個今天", polishEnabled: false))
    }

    func testSecretRoundTripStaysOutOfSyncedFolder() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("open-typeless-test-\(UUID().uuidString)", isDirectory: true)
        let locations = SecretLocations(
            keyringDirectory: root.appendingPathComponent("keys", isDirectory: true),
            keyringFile: root.appendingPathComponent("keys/open-typeless-keyring.json"),
            storeFile: root.appendingPathComponent("private/store.encrypted.json")
        )
        let store = SecretStore(locations: locations)
        let secret = Data("not-a-real-key".utf8)
        try store.save(secret: secret)
        let read = try store.readSecret()
        XCTAssertEqual(read, secret)
        XCTAssertTrue(try store.verify())

        let synced = try String(contentsOf: locations.storeFile, encoding: .utf8)
        XCTAssertFalse(synced.contains("not-a-real-key"))
        XCTAssertFalse(synced.contains("apiKey"))
        XCTAssertTrue(synced.contains("AES-256-GCM"))

        let keyringMode = try FileManager.default.attributesOfItem(atPath: locations.keyringFile.path)[.posixPermissions] as? Int
        XCTAssertEqual(keyringMode, 0o600)

        let bad = SecretLocations(
            keyringDirectory: URL(fileURLWithPath: "/tmp/CloudStorage/keys", isDirectory: true),
            keyringFile: URL(fileURLWithPath: "/tmp/CloudStorage/keys/ring.json"),
            storeFile: root.appendingPathComponent("private/store.encrypted.json")
        )
        XCTAssertThrowsError(try SecretStore(locations: bad).save(secret: secret)) { error in
            XCTAssertEqual(error as? SecretError, .refusingSyncedFolder)
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testPromiseMentionsLocalAudioAndFn() {
        XCTAssertTrue(Promise.beforePermission.contains("Fn"))
        XCTAssertTrue(Promise.beforePermission.contains("不會把錄音傳出去"))
        XCTAssertTrue(Promise.beforePermission.contains("現在還沒有向系統開口"))
        XCTAssertTrue(PermissionPane.inputMonitoring.contains("Privacy_ListenEvent"))
        XCTAssertFalse(PermissionPane.inputMonitoring.contains("Privacy_Accessibility"))
    }

    func testPicksBuiltInMicrophoneNotSteamSpeaker() {
        let listing = """
        AVFoundation video devices:
        [0] MacBook Air相機
        AVFoundation audio devices:
        [0] Steam Streaming Speakers
        [1] MacBook Air的麥克風
        [2] Steam Streaming Microphone
        """
        XCTAssertEqual(AudioInput.pick(from: listing, fallback: ":0"), ":1")
    }

    func testPreferredWordsGoToThePromptAndAreNotForced() {
        let prompt = Terms.prompt(terms: ["Hermes", "權限"])
        XCTAssertTrue(prompt.contains("Hermes, 權限"))
        XCTAssertTrue(prompt.contains("。"))
        XCTAssertFalse(prompt.contains("請"))
        XCTAssertFalse(prompt.contains("全選"))
        XCTAssertFalse(prompt.contains("繁體中文口述"))
    }
}
