import XCTest
@testable import EdgelessTypeCore

final class FullTextCorrectionTests: XCTestCase {
    func testFullReplyAllowsChangedLengthWordsAndPunctuation() throws {
        let output = "請將整段文字整理成通順的句子，並重新安排標點與段落。"
        XCTAssertEqual(try ContextCorrection.correctFullText("測試原文") { _ in output }, output)
        XCTAssertEqual(try ContextCorrection.acceptFullText(String(repeating: output, count: 100)), String(repeating: output, count: 100))
    }
    func testUnchangedReplyAndNonemptyPunctuationAreAccepted() throws {
        XCTAssertEqual(try ContextCorrection.acceptFullText("原文不需要修改。"), "原文不需要修改。")
        XCTAssertEqual(try ContextCorrection.acceptFullText("。"), "。")
        XCTAssertEqual(Policy.plan(mode: .dictation, transcript: "。", polishEnabled: false, acceptModelText: true), .pasteRough("。"))
    }
    func testBlankReplyIsRejectedAndSimplifiedReplyIsConverted() throws {
        for text in ["", "  ", "\n\t"] { XCTAssertThrowsError(try ContextCorrection.acceptFullText(text)) }
        XCTAssertEqual(try ContextCorrection.acceptFullText("这是完整的校正结果。"), "這是完整的校正結果。")
    }
    func testDraftRequestsFullTextWithoutStructuredEdits() throws {
        let body = try ContextCorrection.draft(text: "測試", entries: [], model: "fixture")
        XCTAssertFalse(body.jsonOutput)
        XCTAssertTrue(body.system.contains("直接輸出校正後全文"))
        XCTAssertFalse(body.system.contains("occurrence"))
        XCTAssertFalse(body.system.contains("to 限"))
        XCTAssertFalse(body.timeoutSeconds.isFinite)
    }
    func testAllProvidersDeliverFullTextThroughNormalParsePath() throws {
        let reply = "这是新的完整句子，内容长度与原文不同。"
        for provider in CloudProvider.allCases {
            let fixture: [String: Any]
            switch provider {
            case .xai: fixture = ["choices": [["finish_reason": "stop", "message": ["content": reply]]]]
            case .openai: fixture = ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": reply]]]]]
            case .anthropic: fixture = ["stop_reason": "end_turn", "content": [["type": "text", "text": reply]]]
            case .google: fixture = ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": reply]]]]]]
            }
            let data = try JSONSerialization.data(withJSONObject: fixture)
            let parsed = try CloudWire.parse(data, status: 200, provider: provider)
            XCTAssertEqual(try ContextCorrection.acceptFullText(parsed), "這是新的完整句子，內容長度與原文不同。")
            XCTAssertThrowsError(try CloudWire.parse(data, status: 429, provider: provider))
        }
    }
    func testLaterEmptyChunkNeverReturnsAPartialDraft() {
        var calls = 0
        XCTAssertThrowsError(try ContextCorrection.correctFullText(String(repeating: "測試長文", count: 1000)) { _ in
            calls += 1
            return calls == 1 ? "第一段校正結果。" : " "
        })
        XCTAssertEqual(calls, 2)
    }
}
