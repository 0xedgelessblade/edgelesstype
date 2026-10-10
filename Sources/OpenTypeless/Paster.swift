import AppKit
import OpenTypelessCore

final class Paster {
    var onDismiss: (() -> Void)?
    private(set) var isOffering = false
    private var pendingText: String?
    private var targetPID: pid_t?
    private var targetElement: AXUIElement?
    private var before: PasteSnapshot?
    private var publishedCount = 0
    private var generation = UUID()
    private var verification: Timer?
    private var sending = false
    private let clipboard = ClipboardLease()

    func offer(_ text: String, into pid: pid_t?) {
        cancelOffer()
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpeechContent.hasWords(text) else { return }
        pendingText = text
        targetPID = pid
        isOffering = true
        let board = NSPasteboard.general
        guard clipboard.publish(text) else { return }
        publishedCount = board.changeCount
        guard AXIsProcessTrusted(), let pid,
              let target = NSRunningApplication(processIdentifier: pid) else { return }
        // Re-activating an already active Electron window can disturb focus.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        waitForTarget(pid, token: generation, attempts: 20)
    }

    private func waitForTarget(_ pid: pid_t, token: UUID, attempts: Int) {
        guard token == generation, isOffering else { return }
        if !sending, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
           let element = Self.focusedElement(in: pid) {
            targetElement = element
            before = Self.snapshot(element)
            sendPasteChord(token: token)
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.waitForTarget(pid, token: token, attempts: attempts - 1)
            }
        }
    }

    /// Returns true only when this app takes responsibility for the user's
    /// pending paste. Never call AX APIs while holding an event-tap callback:
    /// the destination may need that very event loop to answer the request.
    func notePasteKey(controlOnly: Bool, fromUs: Bool) -> Bool {
        guard isOffering, !fromUs, !sending,
              NSPasteboard.general.changeCount == publishedCount else { return false }
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, self.isOffering,
                  let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
            self.targetPID = pid
            self.targetElement = Self.focusedElement(in: pid)
            self.before = self.targetElement.map(Self.snapshot)
            self.sendPasteChord(token: token, manual: true)
        }
        return true
    }

    func cancelOffer() {
        generation = UUID()
        verification?.invalidate()
        verification = nil
        isOffering = false
        pendingText = nil
        targetElement = nil
        before = nil
        // Failed/cancelled offers retain the dictated text for manual recovery.
        // Only verified insertion restores the previous clipboard.
        clipboard.discard()
    }

    private func sendPasteChord(token: UUID, manual: Bool = false) {
        guard !sending, token == generation, let pid = targetPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              NSPasteboard.general.changeCount == publishedCount,
              let source = CGEventSource(stateID: .privateState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else { return }
        if let element = targetElement {
            guard let focused = Self.focusedElement(in: pid), CFEqual(element, focused) else { return }
        } else if !manual {
            return
        }
        sending = true
        for event in [commandDown, down, up, commandUp] {
            event.setIntegerValueField(.eventSourceUserData, value: 7941)
        }
        commandDown.flags = .maskCommand
        down.flags = .maskCommand
        up.flags = .maskCommand
        commandUp.flags = []
        // Deliver once to the verified foreground process. The global HID
        // route can cause duplicate paste handling in native and web editors.
        func post(_ event: CGEvent) { event.postToPid(pid) }
        post(commandDown)
        post(down)
        // Keep the run loop free for hotkey monitoring and UI updates.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            // Always release keys, even if this offer was cancelled.
            post(up)
            post(commandUp)
            guard let self else { return }
            self.sending = false
            guard self.generation == token else { return }
            self.startVerification(token: token)
        }
    }

    private func startVerification(token: UUID) {
        verification?.invalidate()
        let deadline = Date().addingTimeInterval(3)
        verification = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self, self.generation == token, self.isOffering else {
                timer.invalidate()
                return
            }
            if let element = self.targetElement, let before = self.before, let text = self.pendingText,
               PasteConfirmation.confirms(text, before: before, after: Self.snapshot(element)) {
                self.clipboard.finish(confirmed: true)
                self.cancelOffer()
                self.onDismiss?()
            } else if Date() >= deadline {
                // Do not retry automatically: delayed/opaque editors could
                // receive the same sentence twice. Leave manual paste ready.
                timer.invalidate()
                self.verification = nil
            }
        }
    }

    static func focusedElement(in pid: pid_t, messagingTimeout: Float = 0.2) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let anchor = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(anchor, messagingTimeout)
        func editable(_ element: AXUIElement) -> AXUIElement? {
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            var role: CFTypeRef?
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            guard [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role as? String ?? ""),
                  subrole as? String != kAXSecureTextFieldSubrole else { return nil }
            return element
        }
        func editableAncestor(_ element: AXUIElement) -> AXUIElement? {
            for name in ["AXEditableAncestor", "AXHighestEditableAncestor"] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
                   let value, CFGetTypeID(value) == AXUIElementGetTypeID(),
                   let result = editable(value as! AXUIElement) { return result }
            }
            return nil
        }
        if let direct = editable(anchor) { return direct }
        if let ancestor = editableAncestor(anchor) { return ancestor }
        // Muse/WebKit hides the contenteditable from AXChildren and reports a
        // button wrapper as focus. Its selected text marker still identifies
        // the actual caret node and that node's editable ancestor. No button
        // action, DOM scan, chat-history read, or direct AX text write is used.
        guard let caret = WebKitFocus.selectionElement(in: anchor) else { return nil }
        AXUIElementSetMessagingTimeout(caret, messagingTimeout)
        return editable(caret) ?? editableAncestor(caret)
    }

    static func snapshot(_ element: AXUIElement) -> PasteSnapshot {
        var value: CFTypeRef?
        var selectedRange: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)
        var selection: NSRange?
        if let selectedRange, CFGetTypeID(selectedRange) == AXValueGetTypeID() {
            let ax = selectedRange as! AXValue
            var range = CFRange()
            if AXValueGetType(ax) == .cfRange, AXValueGetValue(ax, .cfRange, &range),
               range.location >= 0, range.length >= 0 {
                selection = NSRange(location: range.location, length: range.length)
            }
        }
        return PasteSnapshot(value: value as? String, selection: selection)
    }
}
