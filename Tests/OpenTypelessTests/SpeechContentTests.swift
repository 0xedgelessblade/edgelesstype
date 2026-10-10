import XCTest
@testable import OpenTypelessCore

final class SpeechContentTests: XCTestCase {
    func testPunctuationOnlyIsDroppedBeforeEitherMode() {
        for text in ["[BLANK_AUDIO]", "[silence]", "[NO_SPEECH]", "(silence)", "", " ", ".", "。", "...", "…", "，！？」", "\u{200B}.\n", "\u{FEFF}"] {
            XCTAssertFalse(SpeechContent.hasWords(text))
            XCTAssertEqual(Policy.plan(mode: .dictation, transcript: text, polishEnabled: true), .drop("沒有聽到字"))
            XCTAssertEqual(Policy.plan(mode: .translation, transcript: text, polishEnabled: false), .drop("沒有聽到字"))
        }
    }
    func testRealShortWordsNumbersCodeAndEmojiRemain() {
        for text in ["Hi.", "抬棺抗議。", "42", "C++", "你好，world.", "👍"] {
            XCTAssertTrue(SpeechContent.hasWords(text))
            XCTAssertEqual(Policy.plan(mode: .dictation, transcript: text, polishEnabled: false), .pasteRough(text))
        }
    }
    func testSilenceGateDoesNotDropQuietSpeechOrUnknownAudio() {
        func wav(_ values: [Int16]) -> Data {
            var bytes = Data("RIFF".utf8)
            func number(_ x: UInt32, _ count: Int) { for i in 0..<count { bytes.append(UInt8((x >> (8*i)) & 255)) } }
            number(UInt32(36+2*values.count),4); bytes.append(Data("WAVEfmt ".utf8))
            number(16,4);number(1,2);number(1,2);number(16000,4);number(32000,4);number(2,2);number(16,2)
            bytes.append(Data("data".utf8));number(UInt32(2*values.count),4)
            for x in values { number(UInt32(UInt16(bitPattern:x)),2) }
            return bytes
        }
        XCTAssertEqual(SpeechContent.isDigitalSilence(wav([0,1,-1,0])), true)
        XCTAssertEqual(SpeechContent.isDigitalSilence(wav([0,2,-2,0])), false)
        XCTAssertEqual(SpeechContent.isDigitalSilence(wav([0,100,-100,0])), false)
        XCTAssertNil(SpeechContent.isDigitalSilence(Data("not a wav".utf8)))
        XCTAssertNil(SpeechContent.isDigitalSilence(wav([0]).dropLast()))
    }
    func testProtestPhraseCorrectionAndLegitimateOfficials() {
        let cases = [("家人抬官抗議。", "抬官", "抬棺", "家人抬棺抗議。"),
                     ("台官抗議", "台官", "抬棺", "抬棺抗議")]
        for (text, from, to, expected) in cases {
            let response = "{\"corrections\":[{\"from\":\"\(from)\",\"to\":\"\(to)\",\"occurrence\":1}]}"
            XCTAssertTrue(ContextCorrection.sameChineseSound(from,to))
            XCTAssertEqual(ContextCorrection.apply(response: response, to: text, entries: []), expected)
        }
        XCTAssertEqual(ContextCorrection.apply(response: "{\"corrections\":[]}", to: "台灣官員抗議不公平待遇。", entries: []), "台灣官員抗議不公平待遇。")
    }
}
