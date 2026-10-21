import XCTest
@testable import RadioCore

final class PlaybackSessionTests: XCTestCase {
    let first = URL(string: "https://station.example/live.mp3")!
    let second = URL(string: "http://station.example/backup")!

    func testCancelRejectsDelayedRetriesAndCallbacks() {
        var session = PlaybackSession()
        let ticket = session.start(urls: [first])!
        let retry = session.retry(after: ticket)!
        XCTAssertFalse(session.accepts(ticket))
        session.cancel()
        XCTAssertFalse(session.accepts(retry))
        XCTAssertNil(session.retry(after: retry))
    }

    func testNewStationInvalidatesPreviousAttempt() {
        var session = PlaybackSession()
        let old = session.start(urls: [first])!
        let current = session.start(urls: [second])!
        XCTAssertFalse(session.accepts(old))
        XCTAssertNil(session.retry(after: old))
        XCTAssertTrue(session.accepts(current))
    }

    func testRetryBudgetIsFiniteAndAlternatesOnlyKnownURLs() {
        var session = PlaybackSession(maximumAttempts: 4)
        let initial = session.start(urls: [first, second])!
        let a = session.retry(after: initial)!
        let b = session.retry(after: a)!
        let c = session.retry(after: b)!
        XCTAssertEqual([initial.url, a.url, b.url, c.url], [first, second, first, second])
        XCTAssertNil(session.retry(after: c))
        XCTAssertFalse(session.accepts(c))
        XCTAssertNil(session.retry(after: c))
    }

    func testDuplicateFailureDoesNotSpendAnotherRetry() {
        var session = PlaybackSession()
        let initial = session.start(urls: [first])!
        let retry = session.retry(after: initial)!
        XCTAssertNil(session.retry(after: initial))
        XCTAssertTrue(session.accepts(retry))
    }

    func testEmptyAddressesNeverCreateAnAttempt() {
        var session = PlaybackSession()
        XCTAssertNil(session.start(urls: []))
    }
}
