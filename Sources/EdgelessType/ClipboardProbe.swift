import AppKit

enum ClipboardProbe {
    static func run() -> Int32 {
        // An isolated pasteboard: never inspect or replace the user's clipboard.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var failures = 0
        func check(_ name: String, _ passed: Bool) {
            if !passed { failures += 1 }
            print("\(passed ? "PASS" : "FAIL") clipboard-\(name)")
        }
        func text(_ value: String) { board.clearContents(); board.setString(value, forType: .string) }
        let lease = ClipboardLease(board: board)
        text("previous fixture")
        check("publish", lease.publish("dictation fixture") && board.string(forType: .string) == "dictation fixture")
        check("unconfirmed-keeps-manual-paste", !lease.finish(confirmed: false) && board.string(forType: .string) == "dictation fixture")
        check("confirmed-restores-text", lease.finish(confirmed: true) && board.string(forType: .string) == "previous fixture")
        text("previous fixture"); _ = lease.publish("dictation fixture")
        text("new user copy")
        check("preserves-newer-copy", !lease.finish(confirmed: true) && board.string(forType: .string) == "new user copy")
        text("previous fixture"); _ = lease.publish("dictation fixture"); lease.discard()
        check("cancel-keeps-dictation", !lease.finish(confirmed: true) && board.string(forType: .string) == "dictation fixture")
        board.clearContents(); _ = lease.publish("dictation fixture")
        check("restores-empty", lease.finish(confirmed: true) && (board.pasteboardItems ?? []).isEmpty)
        let first = NSPasteboardItem(); first.setString("styled fixture", forType: .string)
        let styled = Data("{\\rtf1 fixture}".utf8); first.setData(styled, forType: .rtf)
        let second = NSPasteboardItem(); second.setData(Data([0,1,2,255]), forType: NSPasteboard.PasteboardType("test.edgelesstype.binary"))
        board.clearContents(); board.writeObjects([first,second]); _ = lease.publish("dictation fixture")
        let restored = lease.finish(confirmed: true)
        let items = board.pasteboardItems ?? []
        check("multiple-items-and-formats", restored && items.count == 2 && items[0].data(forType: .rtf) == styled && items[1].data(forType: NSPasteboard.PasteboardType("test.edgelesstype.binary")) == Data([0,1,2,255]))
        text("newer transaction"); _ = lease.publish("next dictation")
        check("next-offer-has-fresh-backup", lease.finish(confirmed: true) && board.string(forType: .string) == "newer transaction")
        return failures == 0 ? 0 : 1
    }
}
