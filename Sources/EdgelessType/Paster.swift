import AppKit
import EdgelessTypeCore

enum AccessibilityRecoveryKind { case chrome, electron }

final class Paster {
    var onDismiss: (() -> Void)?
    private(set) var isOffering = false
    private(set) var lastInsertionConfirmed = false
    private var pendingText: String?
    private var targetPID: pid_t?
    private var targetElement: AXUIElement?
    private var before: PasteSnapshot?
    private var publishedCount = 0
    private var generation = UUID()
    private var verification: Timer?
    private var sending = false
    private var manualQueued = false
    private var accessibilityRecoveryAttempted = false
    private var diagnosticEvents: [String] = []

    // Temporary local diagnosis: fixed stage names only, never text, clipboard
    // contents, application titles, identifiers, or recordings. Bounded file.
    private func trace(_ stage: String) {
        guard diagnosticEvents.count < 64 else { return }
        diagnosticEvents.append(stage)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("edgelesstype-paste-diagnostic.json")
        if let data = try? JSONSerialization.data(withJSONObject: diagnosticEvents) {
            try? data.write(to: url, options: .atomic)
        }
    }
    private let clipboard = ClipboardLease()

    // Verified opaque editors: ordinary Cmd-V works, but AX may expose no
    // editable field. Keep this narrow; unknown apps still require a target.
    private static func supportsOpaquePaste(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.openai.codex" || bundleIdentifier == "com.anysphere.sand"
    }

    init() {
        trace(AXIsProcessTrusted() ? "startup_accessibility_trusted" : "startup_accessibility_not_trusted")
    }

    func offer(_ text: String, into pid: pid_t?, acceptModelText: Bool = false) {
        cancelOffer()
        diagnosticEvents = []
        lastInsertionConfirmed = false
        trace("offer_started")
        guard let traditional = try? OutputPolicy.forDelivery(text) else {
            trace("traditional_conversion_failed")
            return
        }
        let text = traditional.trimmingCharacters(in: .whitespacesAndNewlines)
        guard acceptModelText ? !text.isEmpty : SpeechContent.hasWords(text) else { return }
        pendingText = text
        targetPID = pid
        isOffering = true
        let board = NSPasteboard.general
        guard clipboard.publish(text) else { trace("clipboard_publish_failed"); return }
        publishedCount = board.changeCount
        guard AXIsProcessTrusted() else { trace("accessibility_not_trusted"); return }
        trace("accessibility_trusted")
        guard let pid else { trace("target_pid_missing"); return }
        guard let target = NSRunningApplication(processIdentifier: pid) else { trace("target_process_missing"); return }
        trace(target.bundleIdentifier == "com.openai.codex" ? "target_is_codex" : "target_is_other")
        // Re-activating an already active Electron window can disturb focus.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        waitForTarget(pid, token: generation, attempts: 20)
    }

    private func waitForTarget(_ pid: pid_t, token: UUID, attempts: Int) {
        guard token == generation, isOffering else { return }
        if !sending, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
           let element = Self.pasteTarget(in: pid) {
            targetElement = element
            before = Self.snapshot(element)
            trace(before?.value == nil ? "target_found_value_unavailable" : "target_found_value_readable")
            sendPasteChord(token: token)
        } else if !sending,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  Self.supportsOpaquePaste(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier) {
            // Observed Codex/Grok Bot behavior: neither app nor system AX focus is
            // exposed, while the ordinary Cmd-V responder path still works.
            // Deliver once to the original foreground process, exactly as in
            // manual recovery. No focus guessing, click, or AX text setter.
            targetElement = nil
            before = nil
            trace(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.anysphere.sand"
                ? "grok_bot_opaque_foreground_fallback" : "codex_opaque_foreground_fallback")
            sendPasteChord(token: token, opaqueAutomatic: true)
        } else if !sending, !accessibilityRecoveryAttempted,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let kind = Self.accessibilityRecoveryKind(for: pid) {
            accessibilityRecoveryAttempted = true
            trace(kind == .chrome ? "chrome_accessibility_requested" : "electron_accessibility_requested")
            Self.requestAccessibilityExposure(in: pid, kind: kind)
            // Chromium (Chrome and Electron apps such as the Claude desktop app)
            // can debounce accessibility activation for about two seconds.
            // Retry detection only; never retry a delivered paste chord.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.waitForTarget(pid, token: token, attempts: 60)
            }
        } else if attempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.waitForTarget(pid, token: token, attempts: attempts - 1)
            }
        } else {
            trace(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid ? "focused_target_unavailable" : "foreground_target_mismatch")
        }
    }

    /// Returns true only when this app takes responsibility for the user's
    /// pending paste. Never call AX APIs while holding an event-tap callback:
    /// the destination may need that very event loop to answer the request.
    func notePasteKey(controlOnly: Bool, fromUs: Bool) -> Bool {
        guard isOffering, !fromUs,
              NSPasteboard.general.changeCount == publishedCount else { return false }
        // Consume repeated/manual chords while one delivery is pending.
        // Passing them through can paste a second copy before readback runs.
        guard !sending, !manualQueued else { return true }
        manualQueued = true
        let token = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token, self.isOffering else { return }
            self.manualQueued = false
            self.trace(controlOnly ? "manual_control_accepted" : "manual_command_accepted")
            guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
            // Automatic delivery may have completed just before this manual
            // request. Check its original baseline before replacing it.
            if self.targetPID == pid, self.insertionConfirmed() {
                self.lastInsertionConfirmed = true
                self.clipboard.finish(confirmed: true)
                self.cancelOffer()
                self.onDismiss?()
                return
            }
            self.verification?.invalidate()
            self.verification = nil
            self.targetPID = pid
            self.targetElement = Self.pasteTarget(in: pid)
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
        manualQueued = false
        accessibilityRecoveryAttempted = false
        pendingText = nil
        targetElement = nil
        before = nil
        // Failed/cancelled offers retain the dictated text for manual recovery.
        // Only verified insertion restores the previous clipboard.
        clipboard.discard()
    }

    private func sendPasteChord(token: UUID, manual: Bool = false, opaqueAutomatic: Bool = false) {
        guard !sending, token == generation, let pid = targetPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              NSPasteboard.general.changeCount == publishedCount,
              let source = CGEventSource(stateID: .privateState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else { return }
        if opaqueAutomatic {
            guard Self.supportsOpaquePaste(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier),
                  targetElement == nil else { return }
        }
        if let element = targetElement {
            guard let focused = Self.pasteTarget(in: pid), CFEqual(element, focused) else { trace("focus_changed_before_send"); return }
        } else if !manual && !opaqueAutomatic {
            trace("automatic_target_missing_before_send")
            return
        }
        trace(manual ? "manual_chord_sent" : "automatic_chord_sent")
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
            if manual || opaqueAutomatic {
                // Opaque editor delivery has no readable insertion evidence.
                // Close the preview after the single chord, retain dictated
                // clipboard text, and record delivery rather than confirmation.
                self.finishManualPaste(manual: manual)
            } else {
                self.startVerification(token: token)
            }
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
            if self.insertionConfirmed() {
                self.trace("automatic_insertion_confirmed")
                self.lastInsertionConfirmed = true
                self.clipboard.finish(confirmed: true)
                self.cancelOffer()
                self.onDismiss?()
            } else if Date() >= deadline {
                self.trace("automatic_confirmation_timeout")
                // Do not retry automatically: delayed/opaque editors could
                // receive the same sentence twice. Leave manual paste ready.
                timer.invalidate()
                self.verification = nil
            }
        }
    }

    private func insertionConfirmed() -> Bool {
        targetElement.flatMap { element in
            before.flatMap { old in pendingText.map {
                PasteConfirmation.confirms($0, before: old, after: Self.snapshot(element))
            }}
        } ?? false
    }

    private func finishManualPaste(manual: Bool) {
        trace(manual ? "manual_preview_dismissed" : "opaque_automatic_preview_dismissed")
        lastInsertionConfirmed = insertionConfirmed()
        if lastInsertionConfirmed { clipboard.finish(confirmed: true) }
        cancelOffer()
        onDismiss?()
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Chromium-based targets hide their AX tree until an assistive client
    /// asks for it. Chrome is matched by bundle ID; Electron apps are matched
    /// by the framework inside their bundle, never by a guessed bundle ID.
    private static func accessibilityRecoveryKind(for pid: pid_t) -> AccessibilityRecoveryKind? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        if app.bundleIdentifier == "com.google.Chrome" { return .chrome }
        return isElectronApp(pid) ? .electron : nil
    }

    private static func isElectronApp(_ pid: pid_t) -> Bool {
        guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return false }
        let framework = bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: framework.path)
    }

    private static func requestAccessibilityExposure(in pid: pid_t, kind: AccessibilityRecoveryKind) {
        guard AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              accessibilityRecoveryKind(for: pid) == kind else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        // Requests process-wide accessibility exposure. No content read or TCC change.
        // Do not disable it afterwards; other assistive clients may depend on it.
        _ = attribute(app, kAXRoleAttribute)
        if kind == .electron {
            // Electron's documented switch for assistive clients other than VoiceOver.
            _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func rawFocus(in pid: pid_t, messagingTimeout: Float = 0.2) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        let focus = elementAttribute(app, kAXFocusedUIElementAttribute)
            ?? elementAttribute(system, kAXFocusedUIElementAttribute)
        guard let focus else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(focus, &owner) == .success, owner == pid else { return nil }
        AXUIElementSetMessagingTimeout(focus, messagingTimeout)
        guard attribute(focus, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return nil }
        return focus
    }

    private static func pasteTarget(in pid: pid_t) -> AXUIElement? {
        if let editor = focusedElement(in: pid) { return editor }
        // Supported opaque apps may expose a wrapper instead of an editor.
        // Cmd-V still goes through the target app's normal responder chain.
        // Require the same foreground PID and AX focus immediately before
        // delivery; never click the wrapper or infer successful insertion.
        guard Self.supportsOpaquePaste(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier) else { return nil }
        return rawFocus(in: pid)
    }

    static func focusedElement(in pid: pid_t, messagingTimeout: Float = 0.2) -> AXUIElement? {
        guard let anchor = rawFocus(in: pid, messagingTimeout: messagingTimeout) else { return nil }
        var visited: [AXUIElement] = []
        func resolve(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 6, visited.count < 16,
                  !visited.contains(where: { CFEqual($0, element) }) else { return nil }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            var owner: pid_t = 0
            guard AXUIElementGetPid(element, &owner) == .success, owner == pid,
                  attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return nil }
            let role = attribute(element, kAXRoleAttribute) as? String ?? ""
            if [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role) { return element }
            // Follow focus/selection relationships only; never search sibling
            // fields or chat history, and never activate a button wrapper.
            for name in [kAXFocusedUIElementAttribute, "AXEditableAncestor", "AXHighestEditableAncestor"] {
                if let linked = elementAttribute(element, name), let result = resolve(linked, depth: depth + 1) { return result }
            }
            if let caret = WebKitFocus.selectionElement(in: element),
               let result = resolve(caret, depth: depth + 1) { return result }
            // A caret may be a static text leaf inside an editable parent.
            if [kAXStaticTextRole, kAXGroupRole].contains(role),
               let parent = elementAttribute(element, kAXParentAttribute) {
                return resolve(parent, depth: depth + 1)
            }
            return nil
        }
        return resolve(anchor, depth: 0)
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
        var text = (value as? String) ?? (value as? NSAttributedString)?.string
        if text == nil,
           let count = attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber,
           count.intValue >= 0, count.intValue <= 1_000_000 {
            var fullRange = CFRange(location: 0, length: count.intValue)
            if let range = AXValueCreate(.cfRange, &fullRange) {
                var result: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                               range, &result) == .success {
                    text = result as? String
                }
            }
        }
        return PasteSnapshot(value: text, selection: selection)
    }
}
