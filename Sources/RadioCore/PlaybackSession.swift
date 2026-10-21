import Foundation

/// A session owns a finite retry budget. Every attempt has a distinct ticket.
/// Platform callbacks must present their ticket before changing player state.
public struct PlaybackSession: Sendable {
    public struct Ticket: Equatable, Sendable {
        public let generation: UUID
        public let attempt: Int
        public let url: URL
    }
    private var generation = UUID()
    private var urls: [URL] = []
    private var attempts = 0
    private var active = false
    public private(set) var ticket: Ticket?
    public let maximumAttempts: Int

    public init(maximumAttempts: Int = 4) { self.maximumAttempts = max(1, maximumAttempts) }

    public mutating func start(urls: [URL]) -> Ticket? {
        cancel()
        self.urls = urls
        active = true
        return advance()
    }

    public func accepts(_ candidate: Ticket) -> Bool { active && ticket == candidate }

    public mutating func retry(after failed: Ticket) -> Ticket? {
        guard accepts(failed) else { return nil }
        return advance()
    }

    public mutating func cancel() {
        active = false; generation = UUID(); attempts = 0; ticket = nil; urls = []
    }

    private mutating func advance() -> Ticket? {
        guard active, !urls.isEmpty, attempts < maximumAttempts else {
            active = false; ticket = nil; return nil
        }
        let next = Ticket(generation: generation, attempt: attempts, url: urls[attempts % urls.count])
        attempts += 1; ticket = next
        return next
    }
}
