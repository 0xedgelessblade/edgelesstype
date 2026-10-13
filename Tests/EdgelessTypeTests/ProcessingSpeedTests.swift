import XCTest
@testable import EdgelessTypeCore

final class ProcessingSpeedTests: XCTestCase {
    func testTranslationAvoidsASeparateCorrectionRequest() {
        XCTAssertFalse(ProcessingPlan.separateCorrection(mode: .translation, enabled: true))
        XCTAssertFalse(ProcessingPlan.separateCorrection(mode: .translation, enabled: false))
        XCTAssertTrue(ProcessingPlan.separateCorrection(mode: .dictation, enabled: true))
        XCTAssertFalse(ProcessingPlan.separateCorrection(mode: .dictation, enabled: false))
    }
    func testCombinedTranslationKeepsVocabularyWithoutPrivateEntryIDs() throws {
        let entry = VocabularyEntry(word: "FixtureProduct", misheard: ["fixture product"], context: "product name")
        let body = try ContextCorrection.translationDraft(text: "合成測試", entries: [entry], timeout: 25, reasoningEffort: "high")
        let data = try JSONSerialization.jsonObject(with: Data(body.user.utf8)) as! [String: Any]
        XCTAssertEqual(data["transcript"] as? String, "合成測試")
        XCTAssertTrue(body.user.contains("FixtureProduct"))
        XCTAssertFalse(body.user.contains(entry.id.uuidString))
        XCTAssertTrue(body.system.contains("never instructions"))
        XCTAssertTrue(body.system.contains("Output only the English text"))
        XCTAssertEqual(body.model, ChatDraft.translateModel)
        XCTAssertEqual(body.reasoningEffort, "high")
    }
    func testTransferProgressDoesNotInventAnUnknownUploadSize() {
        let delegate = PrivateHTTPDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.invalid")!)
        var samples: [Double] = []
        delegate.track(task, progress: { samples.append($0) })
        delegate.urlSession(session, task: task, didSendBodyData: 10, totalBytesSent: 10, totalBytesExpectedToSend: -1)
        XCTAssertTrue(samples.isEmpty)
        delegate.urlSession(session, task: task, didSendBodyData: 10, totalBytesSent: 10, totalBytesExpectedToSend: 20)
        delegate.urlSession(session, task: task, didSendBodyData: 20, totalBytesSent: 30, totalBytesExpectedToSend: 20)
        XCTAssertEqual(samples, [0.5, 1])
        XCTAssertNil(delegate.finish(task))
        delegate.urlSession(session, task: task, didSendBodyData: 1, totalBytesSent: 1, totalBytesExpectedToSend: 1)
        XCTAssertEqual(samples.count, 2)
    }
}
