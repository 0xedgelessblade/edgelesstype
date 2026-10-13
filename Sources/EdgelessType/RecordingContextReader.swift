import AppKit
import EdgelessTypeCore

/// Bounded text-range reads only: no screenshots, HTML, document traversal or full-value fallback.
enum RecordingContextReader {
    private static let queue = DispatchQueue(label: "edgelesstype.recording-context", qos: .userInitiated)
    static func capture(pid: pid_t, into ticket: RecordingContext) {
        let deadline = Date().addingTimeInterval(0.4)
        queue.async {
            guard Date() < deadline, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.04)
            func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
                guard Date() < deadline else { return nil }
                var result: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
                return result
            }
            guard let raw = value(app, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return }
            let field = raw as! AXUIElement
            AXUIElementSetMessagingTimeout(field, 0.04)
            guard let role = value(field, kAXRoleAttribute) as? String,
                  [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return }
            let subrole = value(field, kAXSubroleAttribute) as? String
            let protected = value(field, "AXProtectedContent") as? Bool ?? false
            guard RecordingContext.allowsField(role: role, subrole: subrole, protected: protected) else { return }
            guard let selected = value(field, kAXSelectedTextRangeAttribute), CFGetTypeID(selected) == AXValueGetTypeID(),
                  let count = value(field, kAXNumberOfCharactersAttribute) as? NSNumber else { return }
            var selection = CFRange()
            let axRange = selected as! AXValue
            guard AXValueGetType(axRange) == .cfRange, AXValueGetValue(axRange, .cfRange, &selection),
                  let range = RecordingContext.range(cursor: selection.location, count: count.intValue) else { return }
            var requested = CFRange(location: range.location, length: range.length)
            guard Date() < deadline, let parameter = AXValueCreate(.cfRange, &requested) else { return }
            var content: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(field, kAXStringForRangeParameterizedAttribute as CFString, parameter, &content) == .success,
                  let text = content as? String, Date() < deadline,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let current = value(app, kAXFocusedUIElementAttribute), CFEqual(current, field) else { return }
            ticket.supply(text)
        }
    }
}
