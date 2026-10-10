import XCTest
@testable import OpenTypelessCore

final class VocabularyTests: XCTestCase {
    let entries = VocabularySettings.starter(terms: []).entries

    func testCorrectionRequiresOptInAndSupportsWordOnlyDictionary() {
        let disabled = VocabularySettings(entries: entries)
        XCTAssertTrue(ContextCorrection.candidates(in: "全線", settings: disabled).isEmpty)
        let enabled = VocabularySettings(contextCorrectionEnabled: true, entries: entries)
        XCTAssertEqual(ContextCorrection.candidates(in: "麥克風全線", settings: enabled).map(\.word), entries.map(\.word))
        XCTAssertTrue(ContextCorrection.candidates(in: "", settings: enabled).isEmpty)
    }

    func testContextScopedCorrectionPreservesOtherHomophone() {
        let text = "打開麥克風全線，再查捷運全線通車。"
        let response = """
        {"corrections":[{"from":"全線","to":"權限","occurrence":1}]}
        """
        XCTAssertEqual(ContextCorrection.apply(response: response, to: text, entries: entries), "打開麥克風權限，再查捷運全線通車。")
    }

    func testNoEditPreservesLegitimateWords() {
        for text in ["捷運全線通車。", "公司推出產品。", "全選文字。", "全線", "推出"] {
            XCTAssertEqual(ContextCorrection.apply(response: "{\"corrections\":[]}", to: text, entries: entries), text)
        }
    }

    func testRejectsUnapprovedRewriteAndNewContent() {
        let text = "打開麥克風全線。"
        for replacement in ["打開麥克風權限，然後重新啟動。", "關閉麥克風權限。", "打開相機權限。"] {
            let data = try! JSONSerialization.data(withJSONObject: ["corrections":[["from":"全線","to":replacement,"occurrence":1]]])
            XCTAssertEqual(ContextCorrection.apply(response: String(decoding:data,as:UTF8.self), to:text, entries:entries), text)
        }
    }

    func testRejectsOutOfRangeOccurrence() {
        let text = "全線與全線"
        let response = "{\"corrections\":[{\"from\":\"全線\",\"to\":\"權限\",\"occurrence\":3}]}"
        XCTAssertEqual(ContextCorrection.apply(response:response,to:text,entries:entries),text)
    }

    func testMultipleEditsUseOriginalOffsetsWithEmoji() {
        let text = "👋荷米史的對話框貼完沒有推出。"
        let response = """
        {"corrections":[{"from":"荷米史","to":"Hermes","occurrence":1},{"from":"推出","to":"退出","occurrence":1}]}
        """
        XCTAssertEqual(ContextCorrection.apply(response:response,to:text,entries:entries),"👋Hermes的對話框貼完沒有退出。")
    }

    func testInvalidResponsePreservesOriginal() {
        for response in ["Sorry", "{}", "{\"corrections\":null}", "```json\n{\"edits\":[]}\n```"] {
            XCTAssertEqual(ContextCorrection.apply(response:response,to:"全線",entries:entries),"全線")
        }
    }

    func testDuplicateWordsAreRejected() {
        let settings = VocabularySettings(entries:[VocabularyEntry(word:"Hermes"), VocabularyEntry(word:"hermes")])
        XCTAssertNil(try? settings.validated())
    }

    func testVocabularyRoundTripAndDisabledSetting() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vocabulary-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VocabularyStore(url: root.appendingPathComponent("vocabulary.json"))
        let settings = VocabularySettings(contextCorrectionEnabled:false,entries:entries)
        try! store.save(settings)
        XCTAssertEqual(try! store.load(fallbackTerms:[]), settings)
    }

    func testPayloadContainsOnlyTranscriptAndRelevantVocabulary() {
        let draft = try! ContextCorrection.draft(text:"麥克風全線",entries:[entries[0]],model:"test")
        let payload = try! JSONSerialization.jsonObject(with:Data(draft.user.utf8)) as! [String:Any]
        XCTAssertEqual(Set(payload.keys),Set(["transcript","vocabulary"]))
        XCTAssertFalse(draft.sendsAudio)
    }
    func testChineseIdiomDoesNotRequireDictionaryEntry() {
        let response = """
        {"corrections":[{"from":"人定聖天","to":"人定勝天","occurrence":1}]}
        """
        XCTAssertEqual(ContextCorrection.apply(response:response,to:"人定聖天。",entries:[]),"人定勝天。")
        XCTAssertTrue(ContextCorrection.sameChineseSound("人定聖天", "人定勝天"))
        XCTAssertFalse(ContextCorrection.sameChineseSound("打開", "關閉"))
    }

    func testMixedEnglishIsPreservedAroundChineseCorrection() {
        let response = """
        {"corrections":[{"from":"全線","to":"權限","occurrence":1}]}
        """
        XCTAssertEqual(ContextCorrection.apply(response:response,to:"Please check 麥克風全線, then restart the App.",entries:[]),
                       "Please check 麥克風權限, then restart the App.")
    }

    func testGeneralCorrectionCannotTranslateOrChangeMeaning() {
        for (from,to) in [("hello","你好"),("打開","關閉"),("聖人","勝利")] {
            let payload = try! JSONSerialization.data(withJSONObject:["corrections":[["from":from,"to":to,"occurrence":1]]])
            XCTAssertEqual(ContextCorrection.apply(response:String(decoding:payload,as:UTF8.self),to:from,entries:[]),from)
        }
    }

    func testUniqueLiteralWordDoesNotDependOnModelCounting() {
        let response = """
        {"corrections":[{"from":"全線","to":"權限","occurrence":2}]}
        """
        XCTAssertEqual(ContextCorrection.apply(response:response,to:"請全選這段文字，再檢查應用程式的全線。",entries:[]),
                       "請全選這段文字，再檢查應用程式的權限。")
    }

    func testPublicStarterKeepsEnglishAndOmitsChineseSeeds() {
        let words = VocabularySettings.starter(terms: ["權限", "Hermes", "MyTool"]).entries.map(\.word)
        XCTAssertTrue(words.contains("MyTool"))
        XCTAssertEqual(words.filter { $0 == "Hermes" }.count, 1)
        XCTAssertFalse(words.contains("權限"))
        XCTAssertFalse(words.contains("退出"))
        XCTAssertTrue(words.contains("prompt"))
    }
    func testCorrectionPromptStaysCompactWithoutInternalDictionaryIDs() throws {
        let draft = try ContextCorrection.draft(text: "test", entries: [VocabularyEntry(word: "Hermes")], model: "fixture")
        XCTAssertTrue(draft.system.count <= 550)
        let payload = try JSONSerialization.jsonObject(with: Data(draft.user.utf8)) as! [String: Any]
        let entries = payload["vocabulary"] as! [[String: Any]]
        XCTAssertEqual(Set(entries[0].keys), Set(["word"]))
    }
    func testPunctuationNamesKeepRepeatedWordsAndBeanReferences() {
        let original = "豆點你為什麼會變成是豆豆的豆?應該是豆點句點"
        let response = #"{"corrections":[{"from":"豆點","to":"逗點","occurrence":1},{"from":"豆點","to":"逗點","occurrence":2}],"punctuated":"逗點，你為什麼會變成是豆豆的豆?應該是逗點、句點。"}"#
        XCTAssertEqual(ContextCorrection.validatedApply(response: response, to: original, entries: []),
                       "逗點，你為什麼會變成是豆豆的豆?應該是逗點、句點。")
    }

    func testPunctuationFieldCannotSilentlySubstituteWordsOrSymbols() {
        let original = "這裡應該用豆點，不是句點。"
        // A model must declare word changes instead of hiding them in punctuation.
        let undeclared = #"{"corrections":[],"punctuated":"這裡應該用逗點，不是句點。"}"#
        XCTAssertEqual(ContextCorrection.validatedApply(response: undeclared, to: original, entries: []), original)
        let symbol = #"{"corrections":[{"from":"豆點","to":"，","occurrence":1}],"punctuated":null}"#
        XCTAssertNil(ContextCorrection.validatedApply(response: symbol, to: original, entries: []))
    }

}
