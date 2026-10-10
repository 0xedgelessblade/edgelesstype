import XCTest
@testable import OpenTypelessCore

final class PasteConfirmationTests: XCTestCase {
    func testWebSetterFalseSuccessDoesNotDismiss() {
        let unchanged = PasteSnapshot(value: "", selection: NSRange(location: 0, length: 0))
        XCTAssertFalse(PasteConfirmation.confirms("測試", before: unchanged, after: unchanged))
    }

    func testChineseInsertedAtUTF16CursorAfterEmoji() {
        let before = PasteSnapshot(value: "Hi 👋 end", selection: NSRange(location: 5, length: 0))
        let after = PasteSnapshot(value: "Hi 👋測試 end", selection: NSRange(location: 7, length: 0))
        XCTAssertTrue(PasteConfirmation.confirms("測試", before: before, after: after))
    }

    func testReplacingSelectionWithoutDuplicatingSurroundingText() {
        let before = PasteSnapshot(value: "left OLD right", selection: NSRange(location: 5, length: 3))
        let after = PasteSnapshot(value: "left 新文字 right", selection: NSRange(location: 8, length: 0))
        XCTAssertTrue(PasteConfirmation.confirms("新文字", before: before, after: after))
    }

    func testExistingMatchingSentenceDoesNotCountAsNewPaste() {
        let before = PasteSnapshot(value: "測試", selection: NSRange(location: 2, length: 0))
        XCTAssertFalse(PasteConfirmation.confirms("測試", before: before, after: before))
        XCTAssertFalse(PasteConfirmation.confirms("測試", before: before,
            after: PasteSnapshot(value: "測試!", selection: nil)))
        XCTAssertTrue(PasteConfirmation.confirms("測試", before: before,
            after: PasteSnapshot(value: "測試測試", selection: nil)))
    }

    func testIdenticalReplacementRequiresSelectionToCollapse() {
        let before = PasteSnapshot(value: "測試", selection: NSRange(location: 0, length: 2))
        XCTAssertFalse(PasteConfirmation.confirms("測試", before: before, after: before))
        XCTAssertTrue(PasteConfirmation.confirms("測試", before: before,
            after: PasteSnapshot(value: "測試", selection: NSRange(location: 2, length: 0))))
    }

    func testPlaceholderAndMissingSelectionInWebEditor() {
        XCTAssertTrue(PasteConfirmation.confirms("測試", before: PasteSnapshot(value: "給 Hermes 一個任務", selection: nil),
            after: PasteSnapshot(value: "測試", selection: nil)))
    }

    func testUnavailableValueNeverConfirms() {
        XCTAssertFalse(PasteConfirmation.confirms("測試", before: PasteSnapshot(value: nil, selection: nil),
            after: PasteSnapshot(value: "測試", selection: nil)))
        XCTAssertFalse(PasteConfirmation.confirms("測試", before: PasteSnapshot(value: "", selection: nil),
            after: PasteSnapshot(value: nil, selection: nil)))
    }

    func testInvalidRangeDoesNotCrashOrConfirmUnchangedText() {
        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: 99, length: 3), NSRange(location: 0, length: Int.max)] {
            let before = PasteSnapshot(value: "測試", selection: range)
            XCTAssertFalse(PasteConfirmation.confirms("測試", before: before, after: before))
        }
    }
}
