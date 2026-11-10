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
    /// The cloud answered in the same instant it was abandoned: its text is used, so later cloud steps run as usual.
    public func resumeCloud() { lock.lock(); skippedCloud = false; lock.unlock() }
}

/// Cloud recognition that outlasts its usual time is abandoned by itself once the local draft of the same recording has words.
public final class LocalTakeover: @unchecked Sendable {
    /// 5 s plus an eighth of the 16 kHz mono audio length: a normal reply lands well inside it.
    public static func delay(audioBytes: Int) -> TimeInterval {
        5 + Double(max(0, audioBytes - 44)) / 32_000 / 8
    }

    private let lock = NSLock()
    private var armed = true
    private var fired = false
    private let poll: TimeInterval
    private let queue: DispatchQueue
    private let ready: () -> Bool
    private let cancellation: ProcessingCancellation

    public init(after delay: TimeInterval, poll: TimeInterval = 0.1, queue: DispatchQueue = .global(qos: .userInitiated),
                cancellation: ProcessingCancellation, ready: @escaping () -> Bool) {
        self.poll = poll; self.queue = queue; self.ready = ready; self.cancellation = cancellation
        queue.asyncAfter(deadline: .now() + delay) { self.tick() }
    }

    public var didFire: Bool { lock.lock(); defer { lock.unlock() }; return fired }

    /// After this returns the cloud request is never abandoned by the timer.
    public func disarm() { lock.lock(); armed = false; lock.unlock() }

    private func tick() {
        lock.lock()
        guard armed, !cancellation.isCancelled, !cancellation.didSkipCloud else { armed = false; lock.unlock(); return }
        if ready() {
            armed = false; fired = true
            cancellation.skipCloud()
            lock.unlock()
            return
        }
        lock.unlock()
        queue.asyncAfter(deadline: .now() + poll) { self.tick() }
    }
}

/// Work started on another thread beside the main request; its result is read only if needed.
public final class PendingResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let finished = DispatchSemaphore(value: 0)
    private var result: Result<Value, Error>?

    public init(queue: DispatchQueue = .global(qos: .userInitiated), _ work: @escaping () throws -> Value) {
        queue.async {
            let outcome = Result { try work() }
            self.lock.lock(); self.result = outcome; self.lock.unlock()
            self.finished.signal()
        }
    }

    public var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return result != nil }
    /// The value when the work already ended well; never waits.
    public var finishedValue: Value? { lock.lock(); defer { lock.unlock() }; return try? result?.get() }

    /// Returns at once when the work already finished; a job cancellation stops the wait, not the work.
    public func wait(cancellation: ProcessingCancellation? = nil) throws -> Value {
        while finished.wait(timeout: .now() + 0.05) == .timedOut { try cancellation?.check() }
        finished.signal()
        try cancellation?.check()
        lock.lock(); defer { lock.unlock() }
        return try result!.get()
    }
}
