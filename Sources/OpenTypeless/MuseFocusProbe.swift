import AppKit

/// Read-only compatibility probe. Reports types and counts, never field text.
enum MuseFocusProbe {
    static func run(_ bundle: String, activate: Bool = false, summary: Bool = false) -> Int32 {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return 2 }
        if activate, NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            print("activationRequested=\(target.activate(options: [.activateIgnoringOtherApps]))")
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        print("frontmostPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)")
        print("trusted=\(AXIsProcessTrusted()) targetPID=\(target.processIdentifier)")
        if summary {
            if let editor = Paster.focusedElement(in: target.processIdentifier) {
                let value = Paster.snapshot(editor)
                let text = value.value ?? ""
                print("resolvedEditor=true length=\(text.count) testOccurrences=\(text.components(separatedBy:PasteProbe.text).count-1) onlyTestText=\(!text.isEmpty && text.replacingOccurrences(of:PasteProbe.text,with:"").isEmpty) selectedLength=\(value.selection?.length ?? -1)")
            } else { print("resolvedEditor=false") }
            return 0
        }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        func describe(_ value: CFTypeRef?, _ label: String) {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { print("\(label): unavailable"); return }
            let element = value as! AXUIElement
            AXUIElementSetMessagingTimeout(element, 0.2)
            var pid: pid_t = 0; AXUIElementGetPid(element, &pid)
            let role = attribute(element, kAXRoleAttribute) as? String ?? "unknown"
            let subrole = attribute(element, kAXSubroleAttribute) as? String ?? "none"
            let text = attribute(element, kAXValueAttribute) as? String
            let selected = attribute(element, kAXSelectedTextAttribute) as? String
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            var names: CFArray?
            AXUIElementCopyAttributeNames(element, &names)
            print("\(label): role=\(role) subrole=\(subrole) ownerPID=\(pid) valueLength=\(text?.count ?? -1) selectedLength=\(selected?.count ?? -1) children=\(children.count)")
            print("\(label) attributes=\(names as? [String] ?? [])")
            for name in [kAXTitleAttribute, kAXDescriptionAttribute, "AXSelectedTextMarkerRange", "AXVisibleCharacterRange"] {
                let a = attribute(element, name)
                let string = a as? String
                print("\(label) \(name) present=\(a != nil) length=\(string?.count ?? -1) containsTest=\(string?.contains(PasteProbe.text) ?? false)")
            }
            for name in ["AXEditableAncestor", "AXHighestEditableAncestor", "AXFocusableAncestor"] {
                if let a = attribute(element, name), CFGetTypeID(a) == AXUIElementGetTypeID() {
                    let e = a as! AXUIElement
                    AXUIElementSetMessagingTimeout(e, 0.2)
                    print("\(label) \(name) role=\(attribute(e,kAXRoleAttribute) as? String ?? "unknown") same=\(CFEqual(element,e)) valueLength=\((attribute(e,kAXValueAttribute) as? String)?.count ?? -1)")
                } else { print("\(label) \(name) unavailable") }
            }
            if let caret = WebKitFocus.selectionElement(in: element) {
                AXUIElementSetMessagingTimeout(caret, 0.2)
                let value = attribute(caret,kAXValueAttribute) as? String
                print("\(label) caretElement role=\(attribute(caret,kAXRoleAttribute) as? String ?? "unknown") valueLength=\(value?.count ?? -1) containsTest=\(value?.contains(PasteProbe.text) ?? false)")
                for name in ["AXEditableAncestor", "AXHighestEditableAncestor", kAXParentAttribute] {
                    if let a = attribute(caret,name), CFGetTypeID(a) == AXUIElementGetTypeID() {
                        let e = a as! AXUIElement
                        AXUIElementSetMessagingTimeout(e,0.2)
                        let text=attribute(e,kAXValueAttribute) as? String
                        print("\(label) caret.\(name) role=\(attribute(e,kAXRoleAttribute) as? String ?? "unknown") valueLength=\(text?.count ?? -1) containsTest=\(text?.contains(PasteProbe.text) ?? false)")
                    }
                }
            } else { print("\(label) caretElement unavailable") }
            var parameterNames: CFArray?
            AXUIElementCopyParameterizedAttributeNames(element, &parameterNames)
            print("\(label) parameterized=\(parameterNames as? [String] ?? [])")
            var markerRange: CFTypeRef?
            let markerStatus = AXUIElementCopyParameterizedAttributeValue(element, "AXTextMarkerRangeForUIElement" as CFString, element, &markerRange)
            if markerStatus == .success, let markerRange {
                var text: CFTypeRef?
                let textStatus=AXUIElementCopyParameterizedAttributeValue(element,"AXStringForTextMarkerRange" as CFString,markerRange,&text)
                let string=text as? String
                print("\(label) markerText status=\(textStatus.rawValue) length=\(string?.count ?? -1) containsTest=\(string?.contains(PasteProbe.text) ?? false)")
            } else { print("\(label) markerRange status=\(markerStatus.rawValue)") }
            for (index, child) in children.prefix(8).enumerated() {
                AXUIElementSetMessagingTimeout(child, 0.2)
                print("\(label).child\(index) role=\(attribute(child,kAXRoleAttribute) as? String ?? "unknown") valueLength=\((attribute(child,kAXValueAttribute) as? String)?.count ?? -1)")
            }
            if let nested = attribute(element, kAXFocusedUIElementAttribute), CFGetTypeID(nested) == AXUIElementGetTypeID() {
                let e=nested as! AXUIElement
                print("\(label).focused role=\(attribute(e,kAXRoleAttribute) as? String ?? "unknown") valueLength=\((attribute(e,kAXValueAttribute) as? String)?.count ?? -1)")
            }
        }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.2)
        describe(attribute(app, kAXFocusedUIElementAttribute), "applicationFocus")
        describe(attribute(app, kAXFocusedWindowAttribute), "applicationWindow")
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
            describe(attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute), "systemFocus")
        } else { print("systemFocus skipped: target is not frontmost") }
        return 0
    }
}
