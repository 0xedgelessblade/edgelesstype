import Foundation

public enum Session: Equatable {
    case idle
    case dictation
    case translation
}

public enum TapKind: Equatable {
    case fn
    case fnShift
}

public enum HotkeyAction: Equatable {
    case startDictation
    case startTranslation
    case stopDictation
    case stopTranslation
    case ignore
}

public struct FnGesture: Equatable {
    public var duration: TimeInterval
    public var shiftDuring: Bool

    public init(duration: TimeInterval, shiftDuring: Bool) {
        self.duration = duration
        self.shiftDuring = shiftDuring
    }
}

public enum Hotkey {
    /// A press longer than this is a hold. Holds do nothing.
    public static let defaultTapMax: TimeInterval = 0.8

    public static func classify(_ gesture: FnGesture, maxTap: TimeInterval = defaultTapMax) -> TapKind? {
        guard gesture.duration >= 0, gesture.duration <= maxTap else { return nil }
        return gesture.shiftDuring ? .fnShift : .fn
    }

    /// Fn tap toggles dictation. Fn+Shift only starts translation.
    /// Translation ends with a lone Fn tap, never with Fn+Shift.
    public static func decide(session: Session, tap: TapKind) -> HotkeyAction {
        switch (session, tap) {
        case (.idle, .fn):
            return .startDictation
        case (.idle, .fnShift):
            return .startTranslation
        case (.dictation, .fn):
            return .stopDictation
        case (.translation, .fn):
            return .stopTranslation
        case (.dictation, .fnShift), (.translation, .fnShift):
            return .ignore
        }
    }
}
