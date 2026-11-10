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

    func testParallelLocalResultIsReadyWhenTheCloudIsAbandoned() throws {
        let local = PendingResult { "本機合成文字" }
        XCTAssertEqual(try local.wait(), "本機合成文字")
        XCTAssertTrue(local.isFinished)
        XCTAssertEqual(try local.wait(cancellation: ProcessingCancellation()), "本機合成文字")
    }

    func testCancellingTheJobStopsWaitingForTheLocalResult() {
        let gate = DispatchSemaphore(value: 0)
        let local = PendingResult { () -> String in gate.wait(); return "late" }
        let token = ProcessingCancellation()
        token.cancel()
        XCTAssertThrowsError(try local.wait(cancellation: token))
        XCTAssertFalse(local.isFinished)
        gate.signal()
    }

    func testLocalFailureSurfacesOnlyWhenRead() {
        let local = PendingResult { () -> String in throw ProcessingError.cancelled }
        XCTAssertThrowsError(try local.wait())
    }

    func testLocalTakeoverDelayGrowsWithTheRecording() {
        XCTAssertEqual(LocalTakeover.delay(audioBytes: 0), 5)
        XCTAssertEqual(LocalTakeover.delay(audioBytes: 44 + 32_000 * 16), 7)
        XCTAssertEqual(LocalTakeover.delay(audioBytes: 44 + 32_000 * 80), 15)
    }

    func testSlowCloudIsAbandonedOnceTheLocalDraftHasWords() {
        let token = ProcessingCancellation()
        let abandoned = DispatchSemaphore(value: 0)
        token.register { abandoned.signal() }
        let local = PendingResult { "本機合成文字" }
        _ = try? local.wait()
        let takeover = LocalTakeover(after: 0.05, poll: 0.01, cancellation: token) { local.finishedValue != nil }
        XCTAssertTrue(abandoned.wait(timeout: .now() + 2) == .success)
        XCTAssertTrue(takeover.didFire)
        XCTAssertTrue(token.didSkipCloud)
        XCTAssertFalse(token.isCancelled)
    }

    func testTakeoverWaitsForTheLocalDraftInsteadOfSwitchingToNothing() {
        let token = ProcessingCancellation()
        let abandoned = DispatchSemaphore(value: 0)
        token.register { abandoned.signal() }
        let gate = DispatchSemaphore(value: 0)
        let local = PendingResult { () -> String in gate.wait(); return "late" }
        let takeover = LocalTakeover(after: 0.02, poll: 0.01, cancellation: token) { local.finishedValue != nil }
        XCTAssertFalse(abandoned.wait(timeout: .now() + 0.2) == .success)
        XCTAssertFalse(takeover.didFire)
        gate.signal()
        XCTAssertTrue(abandoned.wait(timeout: .now() + 2) == .success)
        XCTAssertTrue(takeover.didFire)
    }

    func testCloudReplyInTimeDisarmsTheTakeover() {
        let token = ProcessingCancellation()
        let takeover = LocalTakeover(after: 0.05, poll: 0.01, cancellation: token) { true }
        takeover.disarm()
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(takeover.didFire)
        XCTAssertFalse(token.didSkipCloud)
    }

    func testFailedLocalDraftNeverTakesOver() {
        let token = ProcessingCancellation()
        let local = PendingResult { () -> String in throw ProcessingError.cancelled }
        XCTAssertThrowsError(try local.wait())
        XCTAssertNil(local.finishedValue)
        let takeover = LocalTakeover(after: 0.01, poll: 0.01, cancellation: token) { local.finishedValue != nil }
        Thread.sleep(forTimeInterval: 0.15)
        takeover.disarm()
        XCTAssertFalse(token.didSkipCloud)
    }

    func testCloudTextThatWonTheRaceClearsTheSkip() {
        let token = ProcessingCancellation()
        token.skipCloud()
        token.resumeCloud()
        XCTAssertFalse(token.didSkipCloud)
    }

    func testEverySettingsWindowDescribesTheSameSteps() {
        let google = CloudPreferences(provider: .google)
        XCTAssertEqual(PipelineSummary.dictation(backend: .geminiLive, cloud: google, correctionEnabled: true),
                       "辨識：Gemini 即時 · Google 雲端　→　校正：Google gemini-3.6-flash")
        let accurate = CloudPreferences(provider: .google, correctionModels: ["google": "gemini-3.8-flash"])
        XCTAssertEqual(PipelineSummary.dictation(backend: .localWhisper, cloud: accurate, correctionEnabled: true),
                       "辨識：Whisper · 本機　→　校正：Google gemini-3.8-flash")
        XCTAssertEqual(PipelineSummary.dictation(backend: .openAI, cloud: google, correctionEnabled: false),
                       "辨識：GPT Transcribe · OpenAI 雲端　→　校正：關閉")
        // One-pass recognition corrects by itself, so the API window's correction model must not be named.
        let onePass = PipelineSummary.dictation(backend: .geminiDirect, cloud: google, correctionEnabled: true)
        XCTAssertEqual(onePass, "辨識＋校正：Gemini 一趟式 · Google 雲端（gemini-3.8-flash）")
        XCTAssertFalse(onePass.contains("gemini-3.6-flash"))
        XCTAssertEqual(PipelineSummary.translation(cloud: google), "中翻英：Google gemini-3.8-flash")
    }

    func testRoughPasteOfferAppearsOnlyAfterCloudStepsWaitThreeSeconds() {
        XCTAssertFalse(ProcessingPlan.shouldOfferRoughPaste(stage: .correcting, elapsed: 2.9))
        XCTAssertTrue(ProcessingPlan.shouldOfferRoughPaste(stage: .correcting, elapsed: 3))
        XCTAssertTrue(ProcessingPlan.shouldOfferRoughPaste(stage: .translating, elapsed: 3))
        XCTAssertFalse(ProcessingPlan.shouldOfferRoughPaste(stage: .recognizing, elapsed: 9))
        XCTAssertFalse(ProcessingPlan.shouldOfferRoughPaste(stage: .uploading, elapsed: 9))
    }

    func testLocalRecognitionOfferAppearsOnlyAfterCloudRecognitionWaitsTwoSeconds() {
        XCTAssertFalse(ProcessingPlan.shouldOfferLocalRecognition(stage: .uploading, elapsed: 1.9))
        XCTAssertTrue(ProcessingPlan.shouldOfferLocalRecognition(stage: .uploading, elapsed: 2))
        XCTAssertTrue(ProcessingPlan.shouldOfferLocalRecognition(stage: .recognizing, elapsed: 2))
        XCTAssertFalse(ProcessingPlan.shouldOfferLocalRecognition(stage: .correcting, elapsed: 9))
        XCTAssertFalse(ProcessingPlan.shouldOfferLocalRecognition(stage: .translating, elapsed: 9))
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
