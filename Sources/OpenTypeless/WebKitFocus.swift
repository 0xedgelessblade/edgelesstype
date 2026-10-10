import AppKit
import Darwin

/// WebKit can report a role=button wrapper as focus while its caret is in a
/// hidden editable descendant. Resolve the caret's AX element, not the wrapper.
/// Optional runtime symbols: absence leaves the normal AX path unchanged.
enum WebKitFocus {
    private typealias MarkerRangeType = @convention(c) () -> CFTypeID
    private typealias CopyStartMarker = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?

    static func selectionElement(in element: AXUIElement) -> AXUIElement? {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let typeSymbol = dlsym(handle, "AXTextMarkerRangeGetTypeID"),
              let startSymbol = dlsym(handle, "AXTextMarkerRangeCopyStartMarker") else { return nil }
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &range) == .success,
              let range else { return nil }
        let rangeType = unsafeBitCast(typeSymbol, to: MarkerRangeType.self)
        guard CFGetTypeID(range) == rangeType() else { return nil }
        let copyStart = unsafeBitCast(startSymbol, to: CopyStartMarker.self)
        guard let marker = copyStart(range)?.takeRetainedValue() else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXUIElementForTextMarker" as CFString, marker, &selected) == .success,
              let selected, CFGetTypeID(selected) == AXUIElementGetTypeID() else { return nil }
        return (selected as! AXUIElement)
    }
}
