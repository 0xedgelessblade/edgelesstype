import Foundation

public enum ProcessingError: Error { case cancelled, skippedCloud }

/// One token per processing run; callbacks cancel only that run's owned work.
public final class ProcessingCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var skippedCloud = false
    private var callbacks: [UUID: () -> Void] = [:]
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    public var didSkipCloud: Bool { lock.lock(); defer { lock.unlock() }; return skippedCloud }
    public func check() throws { if isCancelled { throw ProcessingError.cancelled } }
    @discardableResult public func register(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        if cancelled { lock.unlock(); callback() }
        else { callbacks[id] = callback; lock.unlock() }
        return id
    }
    public func unregister(_ id: UUID?) {
        guard let id else { return }; lock.lock(); callbacks.removeValue(forKey: id); lock.unlock()
    }
    public func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true; let pending = Array(callbacks.values); callbacks.removeAll(); lock.unlock()
        pending.forEach { $0() }
    }
    /// Abort the in-flight cloud request only. The job continues and pastes the original once.
    public func skipCloud() {
        lock.lock()
        guard !cancelled, !skippedCloud else { lock.unlock(); return }
        skippedCloud = true
        let pending = Array(callbacks.values)
        callbacks.removeAll()
        lock.unlock()
        pending.forEach { $0() }
    }
}
