import XCTest
@testable import OpenTypelessCore

final class SentencePunctuationTests: XCTestCase {
    func testAddsSentenceMarksWithoutChangingMixedLanguage() {
        let original = "我先 check the settings 然後 restart the app 好嗎"
        let punctuated = "我先 check the settings， 然後 restart the app， 好嗎？"
        XCTAssertEqual(SentencePunctuation.validated(punctuated, preserving: original), punctuated)
        XCTAssertEqual(SentencePunctuation.validated("第一句。第二句！", preserving: "第一句第二句"), "第一句。第二句！")
    }
    func testRestoresSpaceOmittedByModelAtAddedComma() {
        XCTAssertEqual(SentencePunctuation.validated("請 check settings，然後 restart，好嗎？", preserving: "請 check settings 然後 restart 好嗎"),
                       "請 check settings， 然後 restart， 好嗎？")
        XCTAssertNil(SentencePunctuation.validated("checksettings。", preserving: "check settings"))
        XCTAssertNil(SentencePunctuation.validated("`let，a = 1`", preserving: "`let a = 1`"))
    }
    func testRejectsRemovedPunctuationAndAnyRewriting() {
        for candidate in ["你好世界。", "你好、世界。", "你好，大家。", "你好，世界。新增"] {
            XCTAssertNil(SentencePunctuation.validated(candidate, preserving: "你好，世界。"))
        }
        XCTAssertNil(SentencePunctuation.validated("Please restart.", preserving: "Please  restart"))
        XCTAssertNil(SentencePunctuation.validated("關閉設定。", preserving: "打開設定"))
    }
    func testProtectsEnglishNumbersURLsPathsAndCode() {
        for (source, candidate) in [
            ("check settings", "che,ck settings"),
            ("版本 3.14", "版本 3.,14"),
            ("https://example.com/a", "https://example.com/a。"),
            ("https://example.com/a", "https://example.com/，a"),
            ("./config.json", "./config.json。"),
            ("`let a = 1`", "`let a = 1。`")
        ] { XCTAssertNil(SentencePunctuation.validated(candidate, preserving: source)) }
        XCTAssertEqual(SentencePunctuation.validated("👋設定好了， 請開 https://example.com/a", preserving: "👋設定好了 請開 https://example.com/a"),
                       "👋設定好了， 請開 https://example.com/a")
    }
    func testEmptyAndPunctuationOnlyCannotCreateOutput() {
        for source in ["", " ", "。", "[BLANK_AUDIO]"] {
            XCTAssertNil(SentencePunctuation.validated("。", preserving: source))
        }
    }
    func testCorrectionAndPunctuationShareOneValidatedResponse() {
        let response = #"{"corrections":[{"from":"全線","to":"權限","occurrence":1}],"punctuated":"請打開麥克風權限，然後 check the settings，好嗎？"}"#
        XCTAssertEqual(ContextCorrection.validatedApply(response: response, to: "請打開麥克風全線然後 check the settings好嗎", entries: []),
                       "請打開麥克風權限，然後 check the settings，好嗎？")
    }
    func testRejectedPunctuationStillKeepsValidWordCorrection() {
        let response = #"{"corrections":[{"from":"全線","to":"權限","occurrence":1}],"punctuated":"刪除麥克風權限。"}"#
        XCTAssertEqual(ContextCorrection.validatedApply(response: response, to: "打開麥克風全線", entries: []), "打開麥克風權限")
        XCTAssertEqual(ContextCorrection.validatedApply(response: #"{"corrections":[],"punctuated":"你好。"}"#, to: "", entries: []), "")
    }
}
