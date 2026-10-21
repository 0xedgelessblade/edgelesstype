import Foundation

/// Numeric transport timing only. No payloads, credentials, URLs or request IDs.
public struct TranscriptionTransferTimings: Codable, Equatable {
    public var uploadSeconds: Double?
    public var responseWaitSeconds: Double?
    public var connectionSeconds: Double?
    public var totalSeconds: Double
    public init(uploadSeconds: Double? = nil, responseWaitSeconds: Double? = nil,
                connectionSeconds: Double? = nil, totalSeconds: Double = 0) {
        self.uploadSeconds = uploadSeconds; self.responseWaitSeconds = responseWaitSeconds
        self.connectionSeconds = connectionSeconds; self.totalSeconds = totalSeconds
    }
    public func merged(with later: TranscriptionTransferTimings) -> TranscriptionTransferTimings {
        func add(_ lhs: Double?, _ rhs: Double?) -> Double? {
            switch (lhs, rhs) { case (nil, nil): return nil; default: return (lhs ?? 0) + (rhs ?? 0) }
        }
        return TranscriptionTransferTimings(
            uploadSeconds: add(uploadSeconds, later.uploadSeconds),
            responseWaitSeconds: add(responseWaitSeconds, later.responseWaitSeconds),
            connectionSeconds: connectionSeconds ?? later.connectionSeconds,
            totalSeconds: totalSeconds + later.totalSeconds)
    }
}

/// Kept separate from the owning client so URLSession does not retain its owner.
final class PrivateHTTPDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var progress: [Int: (Double) -> Void] = [:]
    private var tracked: Set<Int> = []
    private var timings: [Int: TranscriptionTransferTimings] = [:]
    func track(_ task: URLSessionTask, progress callback: ((Double) -> Void)?) {
        lock.lock(); defer { lock.unlock() }; tracked.insert(task.taskIdentifier); progress[task.taskIdentifier] = callback
    }
    func finish(_ task: URLSessionTask) -> TranscriptionTransferTimings? {
        lock.lock(); defer { lock.unlock() }
        tracked.remove(task.taskIdentifier)
        progress.removeValue(forKey: task.taskIdentifier)
        return timings.removeValue(forKey: task.taskIdentifier)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        lock.lock(); let callback = progress[task.taskIdentifier]; lock.unlock()
        callback?(min(1, max(0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        func duration(_ start: Date?, _ end: Date?) -> Double? {
            guard let start, let end, end >= start else { return nil }
            return end.timeIntervalSince(start)
        }
        guard let transaction = metrics.transactionMetrics.last else { return }
        let value = TranscriptionTransferTimings(
            uploadSeconds: duration(transaction.requestStartDate, transaction.requestEndDate),
            responseWaitSeconds: duration(transaction.requestEndDate, transaction.responseStartDate),
            connectionSeconds: duration(transaction.connectStartDate, transaction.connectEndDate),
            totalSeconds: metrics.taskInterval.duration)
        lock.lock(); if tracked.contains(task.taskIdentifier) { timings[task.taskIdentifier] = value }; lock.unlock()
    }
}
