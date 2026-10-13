import AppKit

// Explicit developer test: inserts only this fixed, non-sensitive sentence.
// No recording, network request, Return key, or message submission.
enum PasteProbe {
    static let text = "EdgelessType 測試文字 7941"
    static func run(arguments: [String]) -> Int32 {
        guard (2...3).contains(arguments.count),
              let target = NSRunningApplication.runningApplications(withBundleIdentifier: arguments[1]).first else {
            print("usage: paste-probe <running target bundle identifier> [manual-command|manual-control]")
            return 2
        }
        NSApp.setActivationPolicy(.accessory)
        let paster = Paster()
        let panel = RecordChrome()
        let monitor = HotkeyMonitor()
        defer { withExtendedLifetime(monitor) {} }
        monitor.onPasteKey = { controlOnly, fromUs in
            paster.notePasteKey(controlOnly: controlOnly, fromUs: fromUs)
        }
        let monitoring = monitor.install()
        print("hotkeyMonitor=\(monitoring)")
        var dismissed = false
        paster.onDismiss = { dismissed = true; panel.hide(); print("previewDismissed=true") }
        print("trusted=\(AXIsProcessTrusted()) targetPID=\(target.processIdentifier)")
        func inspect(_ phase: String) {
            var focused: CFTypeRef?
            let app = AXUIElementCreateApplication(target.processIdentifier)
            let status = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
            guard status == .success, let focused else { print("\(phase) focusError=\(status.rawValue)"); return }
            let element = focused as! AXUIElement
            var value: CFTypeRef?
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            let valueStatus = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            let string = value as? String
            var settable = DarwinBoolean(false)
            let writable = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
            if let editor = Paster.focusedElement(in: target.processIdentifier) {
                let value = Paster.snapshot(editor).value ?? ""
                print("\(phase) resolvedLength=\(value.count) copies=\(value.components(separatedBy:text).count-1)")
            }
            print("\(phase) role=\(role as? String ?? "unknown") valueStatus=\(valueStatus.rawValue) valueLength=\(string?.count ?? -1) containsTest=\(string?.contains(text) ?? false) selectedTextSettable=\(settable.boolValue) settableStatus=\(writable.rawValue)")
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            target.activate(options: [.activateIgnoringOtherApps])
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        inspect("before")
        let initial = Paster.focusedElement(in: target.processIdentifier).map(Paster.snapshot)
        var expected: String?
        if let value=initial?.value, let range=initial?.selection,
           range.location <= (value as NSString).length,
           range.length <= (value as NSString).length-range.location {
            expected=(value as NSString).replacingCharacters(in:range,with:text)
        }
        panel.showPending(text)
        let manual = arguments.count == 3
        paster.offer(text, into: manual ? nil : target.processIdentifier)
        if manual {
            // Deliberately publish with no automatic target, then exercise
            // the user's recovery chord through the actual hotkey monitor.
            let control = arguments[2] == "manual-control"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
                    print("manual-probe-aborted: target is no longer frontmost")
                    return
                }
                let source = CGEventSource(stateID: .privateState)
                let modifier: CGKeyCode = control ? 0x3B : 0x37
                let flags: CGEventFlags = control ? .maskControl : .maskCommand
                let modifierDown = CGEvent(keyboardEventSource: source, virtualKey: modifier, keyDown: true)!
                let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)!
                let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)!
                let modifierUp = CGEvent(keyboardEventSource: source, virtualKey: modifier, keyDown: false)!
                modifierDown.flags = flags; down.flags = flags; up.flags = flags; modifierUp.flags = []
                modifierDown.post(tap: .cghidEventTap)
                down.post(tap: .cghidEventTap)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    up.post(tap: .cghidEventTap)
                    modifierUp.post(tap: .cghidEventTap)
                }
            }
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        inspect("after")
        print("offering=\(paster.isOffering) dismissed=\(dismissed)")
        panel.hide()
        withExtendedLifetime(monitor) {}
        let targetHasText = Paster.focusedElement(in: target.processIdentifier)
            .flatMap { Paster.snapshot($0).value }?.contains(text) == true
        let actual = Paster.focusedElement(in: target.processIdentifier).flatMap { Paster.snapshot($0).value }
        let exactlyOnce = expected.map { $0 == actual } ?? targetHasText
        print("resolvedTargetContainsTest=\(targetHasText) exactlyOnce=\(exactlyOnce)")
        return dismissed && !paster.isOffering && targetHasText && exactlyOnce ? 0 : 1
    }
}
