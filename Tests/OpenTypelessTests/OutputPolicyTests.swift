import XCTest
@testable import OpenTypelessCore

final class OutputPolicyTests: XCTestCase {
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
}
