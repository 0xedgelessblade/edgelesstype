import Foundation

/// One decision for a failed or skipped cloud step. The caller pastes at most once.
public struct CloudRecovery: Equatable {
    public var text: String
    public var outcome: String
    public var pasteOnce: Bool
    public var showsNotice: Bool

    public static func correctionFallback(skipped: Bool, cancelled: Bool, failure: CloudError?, transcript: String) -> CloudRecovery {
        if cancelled {
            return CloudRecovery(text: transcript, outcome: "cancelled", pasteOnce: false, showsNotice: false)
        }
        if skipped {
            return CloudRecovery(text: transcript, outcome: "skipped", pasteOnce: true, showsNotice: false)
        }
        let outcome = failure?.rawValue ?? "request_failed"
        return CloudRecovery(text: transcript, outcome: outcome, pasteOnce: true,
                             showsNotice: OutputPolicy.correctionNotice(outcome: outcome) != nil)
    }

    public static func offline(transcript: String) -> CloudRecovery {
        CloudRecovery(text: transcript, outcome: "offline", pasteOnce: true, showsNotice: true)
    }

    /// Translation failure still outputs nothing. Skipping is the only case that pastes the Chinese once.
    public static func translationFallback(skipped: Bool, cancelled: Bool, chinese: String) -> CloudRecovery {
        if skipped && !cancelled {
            return CloudRecovery(text: chinese, outcome: "skipped", pasteOnce: true, showsNotice: false)
        }
        return CloudRecovery(text: chinese, outcome: cancelled ? "cancelled" : "failed", pasteOnce: false, showsNotice: false)
    }
}

/// Whether a keyless host warmup may be sent. The request itself must not carry a credential or body.
public enum ConnectionWarmup {
    public static let minimumInterval: TimeInterval = 60

    public static func shouldSend(offlineProbe: Bool, pathSatisfied: Bool, host: String, now: Date, lastSent: Date?) -> Bool {
        guard !offlineProbe, pathSatisfied, !host.isEmpty else { return false }
        guard let lastSent else { return true }
        return now.timeIntervalSince(lastSent) >= minimumInterval
    }

    /// Host root only. Drops the API path so the warmup cannot look like a model request.
    public static func hostURL(from endpoint: URL) -> URL? {
        guard let host = endpoint.host, !host.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = endpoint.scheme ?? "https"
        parts.host = host
        parts.path = "/"
        return parts.url
    }
}
