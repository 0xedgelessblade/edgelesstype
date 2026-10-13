import XCTest
@testable import EdgelessTypeCore

final class OutputPolicyTests: XCTestCase {
    func testValidationFailuresHavePreciseReasonsWithoutAcceptingInvalidChanges() throws {
        func response(_ changes: [[String: Any]]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: ["corrections": changes]), as: UTF8.self)
        }
        let valid: [String: Any] = ["from": "全線", "to": "權限", "occurrence": 1]
        let cases: [(String, String, CorrectionRejection)] = [
            ("{}", "全線", .invalidJSON),
            (try response(Array(repeating: valid, count: 31)), "全線", .tooManyChanges),
            (try response([["from": "全線。", "to": "權限", "occurrence": 1]]), "全線。", .invalidSource),
            (try response([["from": "全線", "to": "全線", "occurrence": 1]]), "全線", .unchangedReplacement),
            (try response([["from": "今天", "to": "刪除", "occurrence": 1]]), "今天", .disallowedReplacement),
            (try response([["from": "全線", "to": "權限", "occurrence": 0]]), "全線", .invalidOccurrence),
            (try response([valid]), "今天", .sourceNotFound),
            (try response([valid, valid]), "全線", .overlappingChanges)
        ]
        for (json, text, expected) in cases {
            switch ContextCorrection.validatedResult(response: json, to: text, entries: []) {
            case .failure(let reason): XCTAssertEqual(reason, expected)
            case .success: XCTAssertTrue(false)
            }
            XCTAssertNil(ContextCorrection.validatedApply(response: json, to: text, entries: []))
        }
        XCTAssertEqual(try ContextCorrection.validatedResult(response: response([valid]), to: "全線", entries: []).get(), "權限")
    }

    func testPreciseValidationWarningUsesOnlyFixedReasonText() {
        for reason in CorrectionRejection.allCases {
            XCTAssertEqual(OutputPolicy.correctionWarning(outcome: "rejected:" + reason.rawValue),
                reason.explanation + "\n已保留繁體文字，標點可能不完整。")
        }
    }

    func testSimplifiedFallbackBecomesTraditionalLocally() throws {
        XCTAssertEqual(try OutputPolicy.traditional("简体中文测试，请检查网络连接和权限。"), "簡體中文測試，請檢查網絡連接和權限。")
    }
    func testMixedTextKeepsEnglishCodeURLWhitespaceAndEmoji() throws {
        XCTAssertEqual(try OutputPolicy.traditional("\t中文转换 Hello ABC-123 `let x = 1` https://example.com/a?q=1 👨‍👩‍👧‍👦\n"),
                       "\t中文轉換 Hello ABC-123 `let x = 1` https://example.com/a?q=1 👨‍👩‍👧‍👦\n")
    }
    func testTraditionalAndEmptyTextStayValid() throws {
        let text = "繁體中文：權限、發展、頭髮與後臺。"
        XCTAssertEqual(try OutputPolicy.traditional(text), text)
        XCTAssertEqual(try OutputPolicy.traditional(""), "")
    }
    func testEveryFailureWarnsAndSuccessDoesNot() {
        for outcome in ["quota", "authentication", "timeout", "network", "missingKey", "invalidRequest", "incomplete", "rejected", "request_failed"] {
            let warning = OutputPolicy.correctionWarning(outcome: outcome)
            XCTAssertNotNil(warning)
            if outcome != "quota" { XCTAssertTrue(warning!.contains("繁體文字")) }
        }
        for outcome in ["corrected", "unchanged", "not_requested"] {
            XCTAssertNil(OutputPolicy.correctionWarning(outcome: outcome))
        }
        let quota = OutputPolicy.correctionWarning(outcome: "quota")!
        XCTAssertTrue(quota.contains("額度不足或請求過於頻繁"))
        XCTAssertEqual(quota, "服務端額度不足或請求過於頻繁。\n請檢查服務商帳戶或稍後再試。")
    }
    func testLongMixedScriptResultIsConvertedCompletely() throws {
        let unit = "简体中文转换为繁体，English 123。\n"
        let result = try OutputPolicy.traditional(String(repeating: unit, count: 2000))
        XCTAssertEqual(result, String(repeating: "簡體中文轉換為繁體，English 123。\n", count: 2000))
    }
    func testDeliveryRemovesFinalChineseAndEnglishPeriods() throws {
        XCTAssertEqual(try OutputPolicy.forDelivery("简体测试。"), "簡體測試")
        XCTAssertEqual(try OutputPolicy.forDelivery("Hello world. \n"), "Hello world")
        XCTAssertEqual(try OutputPolicy.forDelivery("第一句。第二句。。"), "第一句。第二句")
        XCTAssertEqual(try OutputPolicy.forDelivery("。 . "), "")
    }
    func testDeliveryPreservesInternalPunctuationNumbersAndQuestions() throws {
        for text in ["3.14", "https://example.com", "真的嗎？", "Great!", "你好，世界", "Wait…"] {
            XCTAssertEqual(try OutputPolicy.forDelivery(text), text)
        }
        XCTAssertEqual(try OutputPolicy.forDelivery("It is 3.14. Done."), "It is 3.14. Done")
    }
}
