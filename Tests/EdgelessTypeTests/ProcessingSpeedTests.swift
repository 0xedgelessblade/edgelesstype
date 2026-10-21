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

    func testSkipCloudAbortsTheRequestWithoutCancellingTheJob() throws {
        let token = ProcessingCancellation()
        var fired = 0
        token.register { fired += 1 }
        token.skipCloud()
        XCTAssertFalse(token.isCancelled)
        XCTAssertTrue(token.didSkipCloud)
        XCTAssertEqual(fired, 1)
        try token.check()
        token.skipCloud()
        XCTAssertEqual(fired, 1)
    }

    func testCancelStillStopsTheWholeJobAfterASkipRequest() {
        let token = ProcessingCancellation()
        token.skipCloud()
        token.cancel()
        XCTAssertTrue(token.isCancelled)
        XCTAssertThrowsError(try token.check())
    }

    func testRoughPasteOfferAppearsOnlyAfterCloudStepsWaitThreeSeconds() {
        XCTAssertFalse(ProcessingPlan.shouldOfferRoughPaste(stage: .correcting, elapsed: 2.9))
        XCTAssertTrue(ProcessingPlan.shouldOfferRoughPaste(stage: .correcting, elapsed: 3))
        XCTAssertTrue(ProcessingPlan.shouldOfferRoughPaste(stage: .translating, elapsed: 3))
        XCTAssertFalse(ProcessingPlan.shouldOfferRoughPaste(stage: .recognizing, elapsed: 9))
        XCTAssertFalse(ProcessingPlan.shouldOfferRoughPaste(stage: .uploading, elapsed: 9))
    }

    func testWarmupSendsNoKeyAndSkipsOfflineOrRecentHosts() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(ConnectionWarmup.shouldSend(offlineProbe: true, pathSatisfied: true, host: "api.openai.com", now: now, lastSent: nil))
        XCTAssertFalse(ConnectionWarmup.shouldSend(offlineProbe: false, pathSatisfied: false, host: "api.openai.com", now: now, lastSent: nil))
        XCTAssertFalse(ConnectionWarmup.shouldSend(offlineProbe: false, pathSatisfied: true, host: "", now: now, lastSent: nil))
        XCTAssertTrue(ConnectionWarmup.shouldSend(offlineProbe: false, pathSatisfied: true, host: "api.openai.com", now: now, lastSent: nil))
        XCTAssertFalse(ConnectionWarmup.shouldSend(offlineProbe: false, pathSatisfied: true, host: "api.openai.com", now: now, lastSent: now.addingTimeInterval(-59)))
        XCTAssertTrue(ConnectionWarmup.shouldSend(offlineProbe: false, pathSatisfied: true, host: "api.openai.com", now: now, lastSent: now.addingTimeInterval(-60)))
        let endpoint = CloudProvider.openai.endpoint
        let host = ConnectionWarmup.hostURL(from: endpoint)
        XCTAssertEqual(host?.host, "api.openai.com")
        XCTAssertEqual(host?.path, "/")
        XCTAssertFalse(host?.absoluteString.contains("responses") == true)
    }

    func testSkippedCorrectionPastesTheOriginalOnceAndShowsNothing() {
        let skipped = CloudRecovery.correctionFallback(skipped: true, cancelled: false, failure: .network, transcript: "原文")
        XCTAssertEqual(skipped.text, "原文")
        XCTAssertEqual(skipped.outcome, "skipped")
        XCTAssertTrue(skipped.pasteOnce)
        XCTAssertFalse(skipped.showsNotice)
        let cancelled = CloudRecovery.correctionFallback(skipped: true, cancelled: true, failure: nil, transcript: "原文")
        XCTAssertFalse(cancelled.pasteOnce)
        let offline = CloudRecovery.offline(transcript: "原文")
        XCTAssertEqual(offline.outcome, "offline")
        XCTAssertTrue(offline.pasteOnce)
        XCTAssertTrue(offline.showsNotice)
        let translated = CloudRecovery.translationFallback(skipped: true, cancelled: false, chinese: "中文")
        XCTAssertTrue(translated.pasteOnce)
        XCTAssertEqual(translated.text, "中文")
        XCTAssertFalse(CloudRecovery.translationFallback(skipped: false, cancelled: false, chinese: "中文").pasteOnce)
    }

    func testCorrectionTransferKeepsTheFirstConnectionAndSumsLaterWaits() {
        let first = TranscriptionTransferTimings(uploadSeconds: 0.25, responseWaitSeconds: 1, connectionSeconds: 0.5, totalSeconds: 1.5)
        let later = TranscriptionTransferTimings(uploadSeconds: 0.5, responseWaitSeconds: 2, connectionSeconds: nil, totalSeconds: 2.5)
        let merged = first.merged(with: later)
        XCTAssertEqual(merged.connectionSeconds, 0.5)
        XCTAssertEqual(merged.responseWaitSeconds, 3)
        XCTAssertEqual(merged.uploadSeconds, 0.75)
        XCTAssertEqual(merged.totalSeconds, 4)
    }
}
